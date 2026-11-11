import Testing
@testable import CoinboxCore

@Suite struct BudgetTransferTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.account("sav", .savings); try f.account("mort", .mortgage); try f.category("Mortgage")
        try f.income("chk", "2026-01-01", 2000); try f.assign("Mortgage", "2026-01", 1000)
        return f
    }

    @Test func onBudgetTransferChangesNothingInThePlan() throws {
        let f = try setup()
        let before = try f.summary("2026-01")
        try f.transfer("chk", "sav", "2026-01-05", 500)
        #expect(try f.summary("2026-01") == before)
    }

    @Test func transferToTrackingIsSpending() throws {
        let f = try setup()
        try f.transfer("chk", "mort", "2026-01-05", 1000, category: "Mortgage")
        let m = try #require(try f.summary("2026-01").categories["Mortgage"])
        #expect(m.activity == usd(-1000) && m.available == 0)
    }

    @Test func trackingAccountLinesNeverAffectThePlan() throws {
        let f = try setup()
        let before = try f.summary("2026-01")
        try f.income("mort", "2026-01-05", 5000)
        #expect(try f.summary("2026-01") == before)
    }
}
