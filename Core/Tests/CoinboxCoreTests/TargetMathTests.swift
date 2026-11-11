import Testing
@testable import CoinboxCore

@Suite struct TargetMathTests {
    private func m(_ s: String) -> MonthKey { MonthKey(s)! }

    @Test func monthlyUnderfunded() throws {
        let f = try Fixture()
        try f.category("rent")
        try f.c.perform([.putTarget(Target(categoryID: "rent", cadence: .monthly(day: 1), amount: usd(300)))], author: .mac)
        try f.assign("rent", "2026-01", 120)
        #expect(try f.summary("2026-01").categories["rent"]?.underfunded == usd(180))
        try f.assign("rent", "2026-01", 300)
        #expect(try f.summary("2026-01").categories["rent"]?.underfunded == 0)
    }

    @Test func weeklyUsesWeekdayCount() {
        let t = Target(categoryID: "c", cadence: .weekly(isoWeekday: 1), amount: usd(25))
        #expect(TargetMath.needed(t, in: m("2026-01"), carryover: 0) == usd(100))
        #expect(TargetMath.needed(t, in: m("2026-02"), carryover: 0) == usd(100))
        #expect(TargetMath.needed(t, in: m("2026-06"), carryover: 0) == usd(125))
    }

    @Test func byDateSpreadsOverMonthsLeft() {
        let t = Target(categoryID: "c", cadence: .byDate("2026-06-30"), amount: usd(600))
        #expect(TargetMath.needed(t, in: m("2026-01"), carryover: 0) == usd(100))
        #expect(TargetMath.needed(t, in: m("2026-03"), carryover: usd(200)) == usd(100))
    }

    @Test func yearlyDueNextOccurrence() {
        let t = Target(categoryID: "c", cadence: .yearly(month: 12, day: 15), amount: usd(1200))
        #expect(TargetMath.needed(t, in: m("2026-01"), carryover: 0) == usd(100))
        #expect(TargetMath.needed(t, in: m("2026-12"), carryover: usd(1100)) == usd(100))
    }

    @Test func everyMonthsFirstDueThenRepeats() {
        let t = Target(categoryID: "c", cadence: .everyMonths(n: 3, firstDue: "2026-03-31"), amount: usd(90))
        #expect(TargetMath.needed(t, in: m("2026-01"), carryover: 0) == usd(30))
        #expect(TargetMath.needed(t, in: m("2026-04"), carryover: 0) == usd(30))
    }

    @Test func pastDueByDateNeedsRemainderNow() {
        let t = Target(categoryID: "c", cadence: .byDate("2025-12-31"), amount: usd(300))
        #expect(TargetMath.needed(t, in: m("2026-01"), carryover: usd(100)) == usd(200))
    }

    @Test func monthlyNeedAndCostToBeMe() {
        let jan = m("2026-01")
        let targets = [
            Target(categoryID: "a", cadence: .weekly(isoWeekday: 1), amount: usd(25)),
            Target(categoryID: "b", cadence: .monthly(day: 1), amount: usd(300)),
            Target(categoryID: "c", cadence: .yearly(month: 12, day: 15), amount: usd(1200)),
            Target(categoryID: "d", cadence: .everyMonths(n: 3, firstDue: "2026-03-31"), amount: usd(90)),
            Target(categoryID: "e", cadence: .byDate("2026-06-30"), amount: usd(600)),
        ]
        #expect(TargetMath.monthlyNeed(targets[0], asOf: jan) == 108_333)
        #expect(TargetMath.monthlyNeed(targets[1], asOf: jan) == usd(300))
        #expect(TargetMath.monthlyNeed(targets[2], asOf: jan) == usd(100))
        #expect(TargetMath.monthlyNeed(targets[3], asOf: jan) == usd(30))
        #expect(TargetMath.monthlyNeed(targets[4], asOf: jan) == usd(100))
        #expect(TargetMath.monthlyNeed(Target(categoryID: "x", cadence: .byDate("2025-01-01"), amount: usd(50)), asOf: jan) == 0)
        #expect(TargetMath.costToBeMe(targets, asOf: jan) == 638_333)
    }

    @Test func cardPaymentUnderfunded() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("card", .creditCard); try f.category("groc")
        let P = "card-payment-card"
        try f.income("chk", "2025-12-01", 5000)
        try f.tx("card", "2025-12-31", -500)                                   // starting debt
        try f.assign("groc", "2026-01", 200); try f.tx("card", "2026-01-05", -120, "groc")
        #expect(try f.summary("2026-01").categories[P]?.underfunded == usd(500))
        try f.assign(P, "2026-01", 500)
        #expect(try f.summary("2026-01").categories[P]?.underfunded == 0)
        try f.transfer("chk", "card", "2026-01-25", 620)
        let s = try f.summary("2026-01").categories[P]
        #expect(s?.available == 0 && s?.underfunded == 0)
    }
}
