import Testing
@testable import CoinboxCore

@Suite struct TransactionOpsTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.category("groc"); try f.category("fun"); try f.category("Reimbursed")
        return f
    }

    private func invalid(_ f: Fixture, _ t: Transaction, contains: String? = nil) {
        do { try f.c.perform([.putTransaction(t)], author: .mac); Issue.record("expected a throw") }
        catch let e as CoinboxError {
            guard case let .invalid(why) = e else { Issue.record("wrong error \(e)"); return }
            if let contains { #expect(why.contains(contains)) }
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func splitSumMustEqualAmount() throws {
        let f = try setup()
        invalid(f, Transaction(accountID: "chk", date: "2026-01-02", amount: usd(-50), splits: [SplitLine(categoryID: "groc", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-10))]))
    }

    @Test func splitParentMustHaveNoCategory() throws {
        let f = try setup()
        invalid(f, Transaction(accountID: "chk", date: "2026-01-02", categoryID: "groc", amount: usd(-50), splits: [SplitLine(categoryID: "groc", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-20))]))
    }

    @Test func splitNeedsTwoLines() throws {
        let f = try setup()
        invalid(f, Transaction(accountID: "chk", date: "2026-01-02", amount: usd(-50), splits: [SplitLine(categoryID: "groc", amount: usd(-50))]))
    }

    @Test func outflowToReadyToAssignRefused() throws {
        let f = try setup()
        invalid(f, Transaction(accountID: "chk", date: "2026-01-02", categoryID: "ready-to-assign", amount: usd(-10)), contains: "Ready to Assign")
    }

    @Test func outflowSplitLineToReadyToAssignRefused() throws {
        let f = try setup()
        invalid(f, Transaction(accountID: "chk", date: "2026-01-02", amount: usd(-50), splits: [SplitLine(categoryID: "ready-to-assign", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-20))]), contains: "Ready to Assign")
    }

    @Test func inflowToReadyToAssignAllowed() throws {
        let f = try setup()
        try f.income("chk", "2026-01-02", 10)
        #expect(try f.c.transactions().count == 1)
    }

    @Test func reimbursedInflowIsOrdinary() throws {
        let f = try setup()
        try f.tx("chk", "2026-01-02", 25, "Reimbursed")
        #expect(try f.c.transactions().first?.categoryID == "Reimbursed")
    }

    @Test func unknownAccountOrCategoryIsNotFound() throws {
        let f = try setup()
        #expect(throws: CoinboxError.notFound("account nope")) { try f.c.perform([.putTransaction(Transaction(accountID: "nope", date: "2026-01-02", amount: 1))], author: .mac) }
        #expect(throws: CoinboxError.notFound("category nope")) { try f.c.perform([.putTransaction(Transaction(accountID: "chk", date: "2026-01-02", categoryID: "nope", amount: 1))], author: .mac) }
    }

    @Test func badDateIsInvalid() throws {
        let f = try setup()
        invalid(f, Transaction(accountID: "chk", date: "2026-02-30", amount: 1))
    }

    @Test func putReplacesSplitsAsAUnit() throws {
        let f = try setup()
        let two = [SplitLine(categoryID: "groc", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-20))]
        let three = [SplitLine(categoryID: "groc", amount: usd(-30)), SplitLine(categoryID: "fun", amount: usd(-10)), SplitLine(categoryID: "Reimbursed", amount: usd(-10))]
        try f.tx("chk", "2026-01-02", -50, id: "t", splits: two)
        try f.tx("chk", "2026-01-02", -50, id: "t", splits: three)
        #expect(try f.c.transaction(id: "t")?.splits.count == 3)
        try f.c.undo()
        #expect(try f.c.transaction(id: "t")?.splits == two)
    }

    @Test func deleteAccountWithTransactionsRefused() throws {
        let f = try setup()
        try f.tx("chk", "2026-01-02", -5, "groc")
        do { try f.c.perform([.deleteAccount(id: "chk")], author: .mac); Issue.record("expected a throw") }
        catch let e as CoinboxError { guard case .hasHistory = e else { Issue.record("wrong error \(e)"); return } }
    }
}
