import Testing
@testable import CoinboxCore

@Suite struct MoneyAndMonthTests {
    @Test func format() {
        #expect(Money.format(1_234_560) == "$1,234.56")
        #expect(Money.format(-12_300) == "-$12.30")
        #expect(Money.format(0) == "$0.00")
        #expect(Money.format(1_005) == "$1.01")
        #expect(Money.format(-1_005) == "-$1.01")
    }

    @Test func divideRoundedIsHalfAwayFromZero() {
        #expect(Money.divideRounded(5, 2) == 3)
        #expect(Money.divideRounded(-5, 2) == -3)
        #expect(Money.divideRounded(7, 3) == 2)
    }

    @Test func monthMath() throws {
        #expect(try #require(MonthKey("2026-12")).next.string == "2027-01")
        #expect(try #require(MonthKey("2026-01")).previous.string == "2025-12")
        #expect(try #require(MonthKey("2028-02")).lastDay == "2028-02-29")
        #expect(try #require(MonthKey("2026-02")).lastDay == "2026-02-28")
        #expect(try #require(MonthKey("2026-02")).firstDay == "2026-02-01")
        #expect(MonthKey("2026-13") == nil)
        #expect(MonthKey.containing(date: "2026-03-15")?.string == "2026-03")
        #expect(try #require(MonthKey("2026-11")).monthsThrough(try #require(MonthKey("2027-02"))).count == 4)
        #expect(try #require(MonthKey("2026-11")).monthsThrough(try #require(MonthKey("2026-10"))).isEmpty)
        #expect(try #require(MonthKey("2026-11")).adding(months: 3).string == "2027-02")
    }

    @Test func weekdayCount() throws {
        let jan = try #require(MonthKey("2026-01"))
        #expect(jan.weekdayCount(1) == 4)   // Mondays: 5, 12, 19, 26
        #expect(jan.weekdayCount(4) == 5)   // Thursdays: 1, 8, 15, 22, 29
    }

    @Test func dateValidation() {
        #expect(!MonthKey.isValidDate("2026-02-29"))
        #expect(MonthKey.isValidDate("2028-02-29"))
        #expect(!MonthKey.isValidDate("2026-1-5"))
        #expect(!MonthKey.isValidDate("2026-02-30"))
    }
}
