import Testing
@testable import CoinboxCore

@Suite struct BulkOpsTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.account("sav", .savings); try f.category("groc"); try f.category("fun"); try f.category("fees")
        return f
    }

    private func imported(_ f: Fixture, _ id: String, _ raw: String, _ dollars: Double, date: String = "2026-01-05", account: String = "chk", category: String? = nil) throws {
        try f.c.perform([.putTransaction(Transaction(id: id, accountID: account, date: date, categoryID: category, amount: usd(dollars), approved: false, rawPayee: raw, author: .bank))], author: .bank)
    }

    private func apply(_ f: Fixture, _ b: PlannedBatch) throws { if !b.ops.isEmpty { try f.c.perform(b.ops, author: .claude) } }

    @Test func ruleRenamesCategorizesAndApproves() throws {
        let f = try setup()
        try f.c.perform([.putRule(Rule(id: "r", order: 0, name: "Coffee", payee: TextMatch(.contains, "starbucks"), actions: RuleActions(renamePayee: "Starbucks", categoryID: "fun", approve: true)))], author: .claude)
        try imported(f, "a", "STARBUCKS #12", -5); try imported(f, "b", "STARBUCKS #99", -6)
        let batch = try f.c.planRuleApplication()
        #expect(batch.changes.count == 2 && batch.changes.allSatisfy { $0.payeeAfter == "Starbucks" && $0.categoryAfter == "fun" && $0.approvedAfter && $0.source == "rule Coffee" })
        #expect(batch.ops.filter { if case let .putPayee(p) = $0 { return p.defaultCategoryID == nil } else { return false } }.count == 1)          // the payee is created once
        try apply(f, batch)
        #expect(try f.c.payees().filter { $0.name == "Starbucks" }.count == 1)
        #expect(try f.c.transaction(id: "a")?.approved == true && (try f.c.transaction(id: "b")?.categoryID) == "fun")
        #expect(try f.c.planRuleApplication().changes.isEmpty)       // approved now, nothing left to do
    }

    @Test func existingPayeeIsReusedWhateverTheCase() throws {
        let f = try setup()
        try f.c.perform([.putPayee(Payee(id: "p", name: "Starbucks")), .putRule(Rule(id: "r", name: "C", payee: TextMatch(.contains, "sbux"), actions: RuleActions(renamePayee: "STARBUCKS")))], author: .claude)
        try imported(f, "a", "SBUX 1", -5)
        let batch = try f.c.planRuleApplication()
        try apply(f, batch)
        #expect(try f.c.transaction(id: "a")?.payeeID == "p" && (try f.c.payees().count) == 1)
    }

    @Test func payeeDefaultIsSuggestedButNotApproved() throws {
        let f = try setup()
        try f.c.perform([.putPayee(Payee(id: "p", name: "Trader Joe's", defaultCategoryID: "groc"))], author: .claude)
        try f.c.perform([.putTransaction(Transaction(id: "a", accountID: "chk", date: "2026-01-05", payeeID: "p", amount: usd(-30), approved: false))], author: .bank)
        let batch = try f.c.planRuleApplication()
        #expect(batch.changes.first?.categoryAfter == "groc" && batch.changes.first?.source == "payee default" && batch.changes.first?.approvedAfter == false)
    }

    @Test func firstRuleInOrderWins() throws {
        let f = try setup()
        try f.c.perform([.putRule(Rule(id: "w", order: 1, name: "Vinyl", payee: TextMatch(.contains, "vinyl"), actions: RuleActions(categoryID: "fun"))),
                         .putRule(Rule(id: "i", order: 0, name: "Interest", payee: TextMatch(.contains, "interest"), actions: RuleActions(categoryID: "fees")))], author: .claude)
        try imported(f, "a", "VINYL INTEREST CHARGE", -3)
        #expect(try f.c.planRuleApplication().changes.first?.categoryAfter == "fees")
    }

    @Test func outflowToReadyToAssignIsSkippedAndTheRestApplies() throws {
        let f = try setup()
        try f.c.perform([.putRule(Rule(id: "bad", order: 0, name: "Bad", payee: TextMatch(.contains, "mistake"), actions: RuleActions(categoryID: "ready-to-assign", approve: true))),
                         .putRule(Rule(id: "ok", order: 1, name: "Ok", payee: TextMatch(.contains, "grocer"), actions: RuleActions(categoryID: "groc", approve: true)))], author: .claude)
        try imported(f, "a", "MISTAKE CO", -10); try imported(f, "b", "GROCER", -20)
        let batch = try f.c.planRuleApplication()
        #expect(batch.changes.first { $0.transactionID == "a" }?.skipped?.contains("Ready to Assign") == true)
        try apply(f, batch)
        #expect(try f.c.transaction(id: "a")?.approved == false && (try f.c.transaction(id: "b")?.approved) == true)
    }

    @Test func brokenRegexIsReportedAndNeverMatches() throws {
        let f = try setup()
        try f.c.perform([.putRule(Rule(id: "r", name: "Broken", payee: TextMatch(.regex, "(["), actions: RuleActions(categoryID: "groc")))], author: .claude)
        try imported(f, "a", "ANYTHING", -1)
        #expect(try f.c.planRuleApplication().changes.isEmpty)
        #expect(try f.c.rulesWithBrokenRegex().map(\.id) == ["r"])
    }

    @Test func approvingATransferLegApprovesBothSides() throws {
        let f = try setup()
        try f.transfer("chk", "sav", "2026-01-06", 100)
        for t in try f.c.transactions() { var u = t; u.approved = false; try f.c.perform([.putTransaction(u)], author: .bank) }
        let batch = try f.c.planApprove(ids: [try #require(try f.c.transactions(accountID: "chk").first).id])
        #expect(batch.changes.count == 2 && batch.changes.allSatisfy(\.approvedAfter))
    }

    @Test func approvingALegWhoseSideIsMissingStillApproves() throws {
        let f = try setup()
        try f.c.perform([.putTransaction(Transaction(id: "x", accountID: "chk", date: "2026-01-06", amount: -5, approved: false, transferPairID: "gone"))], author: .bank)
        #expect(try f.c.planApprove(ids: ["x"]).changes.map(\.approvedAfter) == [true])
    }

    @Test func categorizeSkipsSplitsAndOnBudgetTransfersButDoesTheRest() throws {
        let f = try setup()
        try imported(f, "a", "X", -10)
        try f.tx("chk", "2026-01-07", -50, id: "s", splits: [SplitLine(categoryID: "groc", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-20))])
        try f.transfer("chk", "sav", "2026-01-08", 5)
        let leg = try #require(try f.c.transactions(accountID: "sav").first).id
        let batch = try f.c.planCategorize(ids: ["a", "s", leg], categoryID: "groc")
        #expect(batch.changes.first { $0.transactionID == "a" }?.categoryAfter == "groc")
        #expect(batch.changes.first { $0.transactionID == "s" }?.skipped?.contains("split") == true)
        #expect(batch.changes.first { $0.transactionID == leg }?.skipped?.contains("no category") == true)
    }

    @Test func categorizeToReadyToAssignOutflowIsRefused() throws {
        let f = try setup()
        try imported(f, "a", "X", -10)
        #expect(try f.c.planCategorize(ids: ["a"], categoryID: "ready-to-assign").changes.first?.skipped?.contains("Ready to Assign") == true)
    }

    @Test func deleteTakesTheTransferPartnerAlong() throws {
        let f = try setup()
        try f.transfer("chk", "sav", "2026-01-06", 100)
        let leg = try #require(try f.c.transactions(accountID: "chk").first).id
        let batch = try f.c.planDelete(ids: [leg, "nope"])
        #expect(batch.ops.count == 2 && batch.changes.contains { $0.skipped == "not found" })
        try apply(f, batch)
        #expect(try f.c.transactions().isEmpty)
    }

    @Test func previewWritesNothingAndApplyIsOneUndoableChange() throws {
        let f = try setup()
        try imported(f, "a", "X", -10); try imported(f, "b", "Y", -20)
        let before = try opCount(f.c)
        let batch = try f.c.planCategorize(ids: ["a", "b"], categoryID: "groc", approve: true)
        #expect(try opCount(f.c) == before)
        try apply(f, batch)
        #expect(try opCount(f.c) == before + 1)
        try f.c.undo(author: .claude)
        #expect(try f.c.transaction(id: "a")?.categoryID == nil && (try f.c.transaction(id: "b")?.approved) == false)
    }

    // Payee default learning

    private func learning(_ f: Fixture, categories: [String], locked: Bool = false, current: String? = nil) throws {
        try f.c.perform([.putPayee(Payee(id: "p", name: "Shop", defaultCategoryID: current, defaultLocked: locked))], author: .mac)
        for (i, c) in categories.enumerated() {
            try f.c.perform([.putTransaction(Transaction(id: "l\(i)", accountID: "chk", date: "2026-01-0\(i + 1)", payeeID: "p", categoryID: c, amount: -1_000))], author: .mac)
        }
    }

    @Test func twoOfLastThreeFlipTheDefault() throws {
        let f = try setup()
        try learning(f, categories: ["fun", "groc", "groc"], current: "fun")
        #expect(try f.c.learnedDefault(payeeID: "p") == "groc")
    }

    @Test func lockedDefaultNeverChanges() throws {
        let f = try setup()
        try learning(f, categories: ["groc", "groc", "groc"], locked: true, current: "fun")
        #expect(try f.c.learnedDefault(payeeID: "p") == nil)
    }

    @Test func threeDifferentCategoriesLeaveItAlone() throws {
        let f = try setup()
        try learning(f, categories: ["groc", "fun", "fees"], current: "fun")
        #expect(try f.c.learnedDefault(payeeID: "p") == nil)
    }

    @Test func onlyTheLastThreeCount() throws {
        let f = try setup()
        try learning(f, categories: ["fees", "fees", "fees", "groc", "fun", "fun"], current: nil)     // last three: groc, fun, fun
        #expect(try f.c.learnedDefault(payeeID: "p") == "fun")
    }

    @Test func approveAppliesLearnedDefaultInTheSameChange() throws {
        let f = try setup()
        try f.c.perform([.putPayee(Payee(id: "p", name: "Shop"))], author: .mac)
        for i in 1...2 { try f.c.perform([.putTransaction(Transaction(id: "n\(i)", accountID: "chk", date: "2026-01-0\(i)", payeeID: "p", categoryID: "groc", amount: -1_000, approved: false))], author: .bank) }
        try apply(f, try f.c.planApprove(ids: ["n1", "n2"]))
        #expect(try f.c.payee(id: "p")?.defaultCategoryID == "groc")
    }
}
