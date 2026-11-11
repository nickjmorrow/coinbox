import Foundation
import Testing
@testable import CoinboxCore

@Suite struct RuleEngineTests {
    private func tx(_ raw: String?, _ amount: Milliunits = -10_000, account: String = "chk", memo: String? = nil) -> Transaction {
        Transaction(id: "t", accountID: account, date: "2026-01-02", memo: memo, amount: amount, rawPayee: raw)
    }
    private func rule(_ payee: TextMatch? = nil, amount: AmountMatch? = nil, accounts: [String] = [], memo: TextMatch? = nil, order: Int = 0, name: String = "r") -> Rule {
        Rule(id: name, order: order, name: name, payee: payee, amount: amount, accountIDs: accounts, memo: memo, actions: RuleActions(categoryID: "c"))
    }

    @Test func payeeContainsIsCaseInsensitive() {
        #expect(RuleEngine.matches(rule(TextMatch(.contains, "starbucks")), tx("STARBUCKS #1234 SEATTLE")))
        #expect(!RuleEngine.matches(rule(TextMatch(.contains, "dunkin")), tx("STARBUCKS #1234")))
    }

    @Test func payeeEqualsNeedsTheWholeText() {
        #expect(RuleEngine.matches(rule(TextMatch(.equals, "netflix")), tx("Netflix")))
        #expect(!RuleEngine.matches(rule(TextMatch(.equals, "netflix")), tx("Netflix.com")))
    }

    @Test func payeeRegex() {
        #expect(RuleEngine.matches(rule(TextMatch(.regex, "^AMZN.*MKTP")), tx("AMZN Mktp US*2K4")))
        #expect(!RuleEngine.matches(rule(TextMatch(.regex, "^AMZN$")), tx("AMZN Mktp US")))
    }

    @Test func invalidRegexNeverMatchesAndIsDetectable() {
        let broken = TextMatch(.regex, "([")
        #expect(!RuleEngine.matches(rule(broken), tx("anything")))
        #expect(RuleEngine.isBrokenRegex(broken) && !RuleEngine.isBrokenRegex(TextMatch(.regex, "a+")))
    }

    @Test func amountConditions() {
        #expect(RuleEngine.matches(rule(amount: .equals(-10_000)), tx("x")))
        #expect(!RuleEngine.matches(rule(amount: .equals(10_000)), tx("x")))
        #expect(RuleEngine.matches(rule(amount: .range(min: -20_000, max: -5_000)), tx("x")))
        #expect(!RuleEngine.matches(rule(amount: .range(min: -9_000, max: -5_000)), tx("x")))
        #expect(RuleEngine.matches(rule(amount: .endsWithCents(99)), tx("x", -12_990)))
        #expect(RuleEngine.matches(rule(amount: .endsWithCents(99)), tx("x", 12_990)))
        #expect(!RuleEngine.matches(rule(amount: .endsWithCents(99)), tx("x", -12_000)))
    }

    @Test func accountAndMemo() {
        #expect(RuleEngine.matches(rule(accounts: ["chk", "visa"]), tx("x", account: "visa")))
        #expect(!RuleEngine.matches(rule(accounts: ["chk"]), tx("x", account: "visa")))
        #expect(RuleEngine.matches(rule(memo: TextMatch(.contains, "rent")), tx("x", memo: "January Rent")))
        #expect(!RuleEngine.matches(rule(memo: TextMatch(.contains, "rent")), tx("x", memo: nil)))
    }

    @Test func allPresentConditionsMustMatch() {
        let r = rule(TextMatch(.contains, "uber"), amount: .range(min: -50_000, max: 0), accounts: ["chk"])
        #expect(RuleEngine.matches(r, tx("UBER TRIP", -20_000)))
        #expect(!RuleEngine.matches(r, tx("UBER TRIP", -80_000)))
        #expect(!RuleEngine.matches(r, tx("UBER TRIP", -20_000, account: "visa")))
    }

    @Test func fallsBackToThePayeeNameWhenThereIsNoRawText() {
        #expect(RuleEngine.matches(rule(TextMatch(.contains, "netflix")), tx(nil), payeeName: "Netflix"))
        #expect(!RuleEngine.matches(rule(TextMatch(.contains, "netflix")), tx(nil)))
    }

    @Test func orderDecidesTheWinner() {
        let interest = rule(TextMatch(.contains, "interest"), order: 0, name: "Interest")
        let vinyl = rule(TextMatch(.contains, "vinyl"), order: 1, name: "Vinyl")
        let t = tx("VINYL PAYMENT INTEREST CHARGE")
        #expect(RuleEngine.firstMatch([vinyl, interest], for: t)?.name == "Interest")
        #expect(RuleEngine.firstMatch([interest, vinyl], for: tx("VINYL SHOP"))?.name == "Vinyl")
        #expect(RuleEngine.firstMatch([interest, vinyl], for: tx("COFFEE")) == nil)
    }
}

@Suite struct RuleOpsTests {
    @Test func putUndoDeleteRule() throws {
        let c = try Coinbox.inMemory()
        let r = Rule(id: "r1", order: 2, name: "Coffee", payee: TextMatch(.contains, "coffee"), amount: .range(min: -50_000, max: 0), actions: RuleActions(renamePayee: "Coffee", approve: true))
        try c.perform([.putRule(r)], author: .claude)
        #expect(try c.rule(id: "r1") == r && (try c.rules()) == [r])
        try c.perform([.deleteRule(id: "r1")], author: .claude)
        #expect(try c.rules().isEmpty)
        try c.undo(author: .claude)
        #expect(try c.rule(id: "r1") == r)
    }

    @Test func rulesListInOrder() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putRule(Rule(id: "b", order: 2, name: "B", actions: RuleActions())), .putRule(Rule(id: "a", order: 1, name: "A", actions: RuleActions()))], author: .claude)
        #expect(try c.rules().map(\.id) == ["a", "b"])
    }

    @Test func rawPayeeRoundTrips() throws {
        let f = try Fixture()
        try f.account("chk")
        try f.c.perform([.putTransaction(Transaction(id: "t", accountID: "chk", date: "2026-01-02", amount: -5, rawPayee: "SQ *COFFEE SHOP"))], author: .mac)
        #expect(try f.c.transaction(id: "t")?.rawPayee == "SQ *COFFEE SHOP")
    }

    @Test func ynabImportFillsRawPayee() {
        var s = YNABFixture.snapshot()
        s.transactions[0].importPayeeName = "ACME PAYROLL 0042"
        let d = YNABMapper.map(s, since: "2026-01-01")
        #expect(d.transactions.first { $0.id == "ynab-t1" }?.rawPayee == "ACME PAYROLL 0042")
        #expect(d.transactions.first { $0.id == "ynab-t2" }?.rawPayee == nil)          // no payee, no bank text
    }
}

@Suite struct FriendlyJSONTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }

    @Test func enumsUseATypeKey() throws {
        #expect(try decode(CategoryKind.self, #"{"type":"cardPayment","accountID":"visa"}"#) == .cardPayment(accountID: "visa"))
        #expect(try decode(Cadence.self, #"{"type":"byDate","date":"2026-06-30"}"#) == .byDate("2026-06-30"))
        #expect(try decode(Cadence.self, #"{"type":"everyMonths","n":3,"firstDue":"2026-03-31"}"#) == .everyMonths(n: 3, firstDue: "2026-03-31"))
        #expect(try decode(AmountMatch.self, #"{"type":"range","min":-5,"max":0}"#) == .range(min: -5, max: 0))
        let round = try JSONEncoder().encode(Cadence.yearly(month: 12, day: 15))
        #expect(try decode(Cadence.self, String(decoding: round, as: UTF8.self)) == .yearly(month: 12, day: 15))
        #expect(throws: (any Error).self) { try decode(Cadence.self, #"{"type":"sometimes"}"#) }
    }

    @Test func shortJSONFillsDefaults() throws {
        let t = try decode(Transaction.self, #"{"accountID":"chk","date":"2026-01-02","amount":-5000}"#)
        #expect(t.approved && t.cleared == .uncleared && t.splits.isEmpty && !t.id.isEmpty)
        let a = try decode(Account.self, #"{"name":"Visa","kind":"creditCard"}"#)
        #expect(a.onBudget && !a.closed && a.kind == .creditCard)
        let c = try decode(Category.self, #"{"groupID":"g","name":"Rent"}"#)
        #expect(c.kind == .normal && !c.hidden)
        let r = try decode(Rule.self, #"{"name":"Coffee","payee":{"mode":"contains","text":"sbux"},"actions":{"categoryID":"fun","approve":true}}"#)
        #expect(r.actions.approve && r.actions.categoryID == "fun" && r.accountIDs.isEmpty)
    }
}

@Suite struct AccountDefaultsTests {
    @Test func trackingKindsDefaultToOffBudget() throws {
        let m = try JSONDecoder().decode(Account.self, from: Data(#"{"name":"House","kind":"mortgage"}"#.utf8))
        #expect(!m.onBudget)
        #expect(try JSONDecoder().decode(Account.self, from: Data(#"{"name":"Chk"}"#.utf8)).onBudget)
    }
}
