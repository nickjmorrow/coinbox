import Testing
@testable import CoinboxCore

@Suite struct BudgetOverspendingTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.account("card", .creditCard); try f.category("groc")
        return f
    }

    @Test func cashOverspendReducesNextRTA() throws {
        let f = try setup()
        try f.income("chk", "2026-01-02", 1000); try f.assign("groc", "2026-01", 100); try f.tx("chk", "2026-01-10", -150, "groc")
        let g = try #require(try f.summary("2026-01").categories["groc"])
        #expect(g.cashOverspent == usd(50) && g.creditOverspent == 0)
        #expect(try f.summary("2026-01").readyToAssign == usd(900))
        #expect(try f.summary("2026-02").readyToAssign == usd(850))
        #expect(try f.summary("2026-02").categories["groc"]?.carryover == 0)
    }

    @Test func creditOverspendDoesNotTouchRTA() throws {
        let f = try setup()
        try f.income("chk", "2026-01-02", 1000); try f.assign("groc", "2026-01", 100); try f.tx("card", "2026-01-10", -150, "groc")
        let g = try #require(try f.summary("2026-01").categories["groc"])
        #expect(g.creditOverspent == usd(50) && g.cashOverspent == 0)
        #expect(try f.summary("2026-02").readyToAssign == usd(900))
    }

    @Test func mixedCashThenCard() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("chk", "2026-01-03", -80, "groc"); try f.tx("card", "2026-01-04", -60, "groc")
        let g = try #require(try f.summary("2026-01").categories["groc"])
        #expect(g.available == usd(-40) && g.creditOverspent == usd(40) && g.cashOverspent == 0)
    }

    @Test func mixedCardThenCash() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("card", "2026-01-03", -30, "groc"); try f.tx("chk", "2026-01-04", -120, "groc")
        let g = try #require(try f.summary("2026-01").categories["groc"])
        #expect(g.available == usd(-50) && g.creditOverspent == usd(30) && g.cashOverspent == usd(20))
    }

    @Test func cardRefundNetsAgainstCardSpending() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("card", "2026-01-03", -150, "groc"); try f.tx("card", "2026-01-05", 30, "groc")
        let g = try #require(try f.summary("2026-01").categories["groc"])
        #expect(g.available == usd(-20) && g.creditOverspent == usd(20))
    }

    @Test func fundedLaterInMonthIsNotOverspent() throws {
        let f = try setup()
        try f.tx("chk", "2026-01-02", -150, "groc"); try f.assign("groc", "2026-01", 200)
        let g = try #require(try f.summary("2026-01").categories["groc"])
        #expect(g.available == usd(50) && g.cashOverspent == 0 && g.creditOverspent == 0)
    }
}
