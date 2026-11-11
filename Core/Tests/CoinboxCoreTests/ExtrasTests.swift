import Testing
@testable import CoinboxCore

@Suite struct PayoffPlannerTests {
    private func card(_ id: String, owed: Double, apr: Int, min: Double) -> PayoffCard { PayoffCard(id: id, name: id, owed: usd(owed), aprBasisPoints: apr, minimumPayment: usd(min)) }
    private let jan = MonthKey(year: 2026, month: 1)

    @Test func firstMonthInterestAndPayment() {
        let p = PayoffPlanner.plan(cards: [card("a", owed: 1000, apr: 1200, min: 50)], monthlyBudget: usd(50), strategy: .avalanche, start: jan)
        #expect(p.schedule[0].payments["a"] == usd(50) && p.schedule[0].remaining == usd(960))      // 1000 + 10.00 interest − 50
    }

    @Test func zeroInterestPaysOffInTheObviousNumberOfMonths() {
        let p = PayoffPlanner.plan(cards: [card("a", owed: 1000, apr: 0, min: 25)], monthlyBudget: usd(250), strategy: .avalanche, start: jan)
        #expect(p.months == 4 && p.debtFreeMonth == "2026-04" && p.totalInterest == 0 && p.cards[0].paidOffIn == "2026-04")
    }

    @Test func avalancheTargetsTheHighestRate() {
        let cards = [card("a", owed: 500, apr: 2400, min: 25), card("b", owed: 400, apr: 1200, min: 25)]
        let p = PayoffPlanner.plan(cards: cards, monthlyBudget: usd(300), strategy: .avalanche, start: jan)
        #expect(p.schedule[0].payments["a"] == usd(275) && p.schedule[0].payments["b"] == usd(25))
    }

    @Test func snowballTargetsTheSmallestBalance() {
        let cards = [card("a", owed: 500, apr: 2400, min: 25), card("b", owed: 400, apr: 1200, min: 25)]
        let p = PayoffPlanner.plan(cards: cards, monthlyBudget: usd(300), strategy: .snowball, start: jan)
        #expect(p.schedule[0].payments["b"] == usd(275) && p.schedule[0].payments["a"] == usd(25))
    }

    @Test func extraMoneyBeatsMinimumsOnly() {
        let cards = [card("a", owed: 3000, apr: 2200, min: 90)]
        let p = PayoffPlanner.plan(cards: cards, monthlyBudget: usd(300), strategy: .avalanche, start: jan)
        #expect((p.interestSaved ?? 0) > 0 && (p.minimumOnlyInterest ?? 0) > p.totalInterest && (p.months ?? 999) < 15)
    }

    @Test func freedMinimumsRollOverToTheNextCard() {
        let cards = [card("a", owed: 100, apr: 2400, min: 25), card("b", owed: 900, apr: 1200, min: 25)]
        let p = PayoffPlanner.plan(cards: cards, monthlyBudget: usd(200), strategy: .avalanche, start: jan)
        #expect(p.cards.first { $0.name == "a" }?.paidOffIn == "2026-01")
        #expect((p.schedule[1].payments["b"] ?? 0) == usd(200))        // a is gone, so all of the budget goes to b
    }

    @Test func warnsWhenTheBudgetIsBelowMinimumsOrTheMinimumNeverBeatsInterest() {
        let p = PayoffPlanner.plan(cards: [card("a", owed: 10_000, apr: 2999, min: 100)], monthlyBudget: usd(50), strategy: .avalanche, start: jan)
        #expect(p.warnings.contains { $0.contains("less than the minimums") } && p.warnings.contains { $0.contains("never pays off") })
        #expect(p.debtFreeMonth == nil && p.months == nil)
    }

    @Test func cardsWithNoBalanceAreLeftOut() {
        let p = PayoffPlanner.plan(cards: [card("a", owed: 0, apr: 1200, min: 25)], monthlyBudget: usd(100), strategy: .avalanche, start: jan)
        #expect(p.cards.isEmpty && p.totalInterest == 0)
    }
}

@Suite struct ExtrasOpsTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.account("visa", .creditCard)
        for c in ["home", "pets", "books"] { try f.category(c) }
        return f
    }

    @Test func cardTermsAreOpsAndNeedACreditCard() throws {
        let f = try setup()
        try f.c.perform([.putCardTerms(CardTerms(accountID: "visa", aprBasisPoints: 2499, minimumPayment: usd(35)))], author: .mac)
        #expect(try f.c.cardTerms() == [CardTerms(accountID: "visa", aprBasisPoints: 2499, minimumPayment: usd(35))])
        try f.c.undo()
        #expect(try f.c.cardTerms().isEmpty)
        #expect(throws: CoinboxError.self) { try f.c.perform([.putCardTerms(CardTerms(accountID: "chk", aprBasisPoints: 100, minimumPayment: 0))], author: .mac) }
    }

    @Test func payoffPlanUsesBalancesAndTermsAndFlagsMissingTerms() throws {
        let f = try setup()
        try f.account("amex", .creditCard)
        try f.tx("visa", "2026-01-02", -1000); try f.tx("amex", "2026-01-02", -500)
        try f.c.perform([.putCardTerms(CardTerms(accountID: "visa", aprBasisPoints: 0, minimumPayment: usd(25)))], author: .mac)
        let plan = try f.c.payoffPlan(strategy: .avalanche, monthlyBudget: usd(250), start: MonthKey("2026-02")!)
        #expect(plan.cards.map(\.name) == ["visa"] && plan.months == 4 && plan.debtFreeMonth == "2026-05")
        #expect(plan.warnings.contains { $0.contains("amex") && $0.contains("no APR") })
    }

    @Test func amazonSplitProratesTaxAndAddsUp() throws {
        let f = try setup()
        try f.tx("visa", "2026-01-05", -64.30, id: "amz")
        let ops = try f.c.amazonSplitOps(transactionID: "amz", orderID: "111-2223334-5556667",
                                         items: [AmazonItem(name: "Dog bed", amount: usd(40), categoryID: "pets"), AmazonItem(name: "Novel", amount: usd(20), categoryID: "books")], tax: usd(4.30))
        try f.c.perform(ops, author: .claude)
        let t = try #require(try f.c.transaction(id: "amz"))
        #expect(t.categoryID == nil && t.splits.map(\.amount) == [usd(-42.867), usd(-21.433)] && t.splits.reduce(0, { $0 + $1.amount }) == t.amount)
        #expect(t.splits.map(\.memo) == ["Dog bed", "Novel"])
        #expect(try f.c.amazonLink(transactionID: "amz")?.orderID == "111-2223334-5556667")
        #expect(try f.summary("2026-01").categories["pets"]?.activity == usd(-42.867))
    }

    @Test func taxIsDerivedWhenNotGiven() throws {
        let f = try setup()
        try f.tx("visa", "2026-01-05", -30.00, id: "amz")
        let ops = try f.c.amazonSplitOps(transactionID: "amz", orderID: "o", items: [AmazonItem(name: "a", amount: usd(10), categoryID: "pets"), AmazonItem(name: "b", amount: usd(18), categoryID: "books")], tax: nil)
        try f.c.perform(ops, author: .claude)
        #expect(try f.c.amazonLink(transactionID: "amz")?.tax == usd(2))
    }

    @Test func rowsThatDontAddUpAreRefused() throws {
        let f = try setup()
        try f.tx("visa", "2026-01-05", -30.00, id: "amz")
        #expect(throws: CoinboxError.self) { _ = try f.c.amazonSplitOps(transactionID: "amz", orderID: "o", items: [AmazonItem(name: "a", amount: usd(10), categoryID: "pets"), AmazonItem(name: "b", amount: usd(10), categoryID: "books")], tax: usd(1)) }
        #expect(throws: CoinboxError.self) { _ = try f.c.amazonSplitOps(transactionID: "amz", orderID: "o", items: [], tax: nil) }
        #expect(throws: CoinboxError.self) { _ = try f.c.amazonSplitOps(transactionID: "nope", orderID: "o", items: [AmazonItem(name: "a", amount: 1, categoryID: "pets")], tax: nil) }
    }

    @Test func oneItemNeedsNoSplit() throws {
        let f = try setup()
        try f.tx("visa", "2026-01-05", -21.60, id: "amz")
        try f.c.perform(try f.c.amazonSplitOps(transactionID: "amz", orderID: "o", items: [AmazonItem(name: "Leash", amount: usd(20), categoryID: "pets")], tax: usd(1.60)), author: .claude)
        let t = try #require(try f.c.transaction(id: "amz"))
        #expect(t.categoryID == "pets" && t.splits.isEmpty)
    }

    @Test func aRefundSplitsWithPositiveLines() throws {
        let f = try setup()
        try f.tx("visa", "2026-01-09", 10.50, id: "ref")
        try f.c.perform(try f.c.amazonSplitOps(transactionID: "ref", orderID: "o", items: [AmazonItem(name: "a", amount: usd(5), categoryID: "pets"), AmazonItem(name: "b", amount: usd(5), categoryID: "books")], tax: usd(0.5)), author: .claude)
        #expect(try f.c.transaction(id: "ref")?.splits.map(\.amount) == [usd(5.25), usd(5.25)])
    }

    @Test func undoRestoresTheOriginalChargeAndDropsTheLink() throws {
        let f = try setup()
        try f.tx("visa", "2026-01-05", -30.00, id: "amz")
        try f.c.perform(try f.c.amazonSplitOps(transactionID: "amz", orderID: "o", items: [AmazonItem(name: "a", amount: usd(10), categoryID: "pets"), AmazonItem(name: "b", amount: usd(18), categoryID: "books")], tax: nil), author: .claude)
        try f.c.undo(author: .claude)
        #expect(try f.c.transaction(id: "amz")?.splits.isEmpty == true && (try f.c.amazonLink(transactionID: "amz")) == nil)
    }

    @Test func deletingASplitChargeAlsoRemovesItsLinkAndUndoBringsBothBack() throws {
        let f = try setup()
        try f.tx("visa", "2026-01-05", -30.00, id: "amz")
        try f.c.perform(try f.c.amazonSplitOps(transactionID: "amz", orderID: "o", items: [AmazonItem(name: "a", amount: usd(10), categoryID: "pets"), AmazonItem(name: "b", amount: usd(18), categoryID: "books")], tax: nil), author: .claude)
        try f.c.perform(try f.c.planDelete(ids: ["amz"]).ops, author: .claude)
        #expect(try f.c.amazonLinks().isEmpty)
        try f.c.undo(author: .claude)
        #expect(try f.c.amazonLink(transactionID: "amz") != nil && (try f.c.transaction(id: "amz")?.splits.count) == 2)
    }
}
