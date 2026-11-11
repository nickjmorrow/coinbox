import Testing
@testable import CoinboxCore

@Suite struct BudgetBasicsTests {
    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.category("groc")
        return f
    }

    @Test func rtaIsInflowsMinusAssigned() throws {
        let f = try setup()
        try f.income("chk", "2026-01-05", 3000); try f.assign("groc", "2026-01", 1000)
        #expect(try f.summary("2026-01").readyToAssign == usd(2000))
    }

    @Test func futureAssignmentReducesEarlierRTA() throws {
        let f = try setup()
        try f.income("chk", "2026-01-05", 3000); try f.assign("groc", "2026-01", 1000); try f.assign("groc", "2026-02", 500)
        #expect(try f.summary("2026-01").readyToAssign == usd(1500))
    }

    @Test func laterInflowDoesNotCountEarlier() throws {
        let f = try setup()
        try f.income("chk", "2026-01-05", 3000); try f.income("chk", "2026-02-03", 100)
        #expect(try f.summary("2026-01").readyToAssign == usd(3000))
        #expect(try f.summary("2026-02").readyToAssign == usd(3100))
    }

    @Test func overassigningGoesNegative() throws {
        let f = try setup()
        try f.income("chk", "2026-01-05", 1000); try f.assign("groc", "2026-01", 1500)
        #expect(try f.summary("2026-01").readyToAssign == usd(-500))
    }

    @Test func availableIsAssignedPlusActivity() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 400); try f.tx("chk", "2026-01-10", -150, "groc")
        let g = try #require(try f.summary("2026-01").categories["groc"])
        #expect(g.assigned == usd(400) && g.activity == usd(-150) && g.available == usd(250))
    }

    @Test func positiveBalanceCarriesOver() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 400); try f.tx("chk", "2026-01-10", -150, "groc")
        try f.assign("groc", "2026-02", 100); try f.tx("chk", "2026-02-10", -50, "groc")
        let g = try #require(try f.summary("2026-02").categories["groc"])
        #expect(g.carryover == usd(250) && g.available == usd(300))
    }

    @Test func negativeBalanceDoesNotCarry() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("chk", "2026-01-10", -150, "groc"); try f.assign("groc", "2026-02", 20)
        #expect(try f.summary("2026-01").categories["groc"]?.available == usd(-50))
        let g = try #require(try f.summary("2026-02").categories["groc"])
        #expect(g.carryover == 0 && g.available == usd(20))
    }

    @Test func emptyDatabaseIsAllZero() throws {
        let f = try Fixture()
        let s = try f.summary("2026-05")
        #expect(s.readyToAssign == 0 && s.cashOverspending == 0)
        #expect(s.categories.values.allSatisfy { $0 == CategoryMonth() })
    }

    @Test func uncategorizedSpendingIsCashOverspendingThatReducesNextMonth() throws {
        let f = try setup()
        try f.account("visa", .creditCard)
        try f.income("chk", "2026-01-05", 100)
        try f.tx("chk", "2026-01-06", -30); try f.tx("visa", "2026-01-07", -10)
        let jan = try f.summary("2026-01")
        let u = try #require(jan.categories["uncategorized"])
        #expect(u.activity == usd(-40) && u.available == usd(-40) && u.creditOverspent == usd(10) && u.cashOverspent == usd(30))
        #expect(jan.readyToAssign == usd(100) && jan.cashOverspending == usd(30))
        #expect(try f.summary("2026-02").readyToAssign == usd(70))
        try f.c.perform([.putTransaction(Transaction(id: "t2", accountID: "chk", date: "2026-01-06", categoryID: "groc", amount: usd(-30)))], author: .mac)     // categorizing it moves it out of Uncategorized
        try f.assign("groc", "2026-01", 30)
        let after = try f.summary("2026-01")
        #expect(after.cashOverspending == 0 && after.categories["uncategorized"]?.cashOverspent == 0 && after.categories["uncategorized"]?.creditOverspent == usd(10))
    }

    @Test func transfersAndPaymentsAreNotUncategorizedSpending() throws {
        let f = try setup()
        try f.account("sav", .savings); try f.income("chk", "2026-01-05", 100)
        try f.transfer("chk", "sav", "2026-01-06", 50)
        #expect(try f.summary("2026-01").categories["uncategorized"] == nil)
    }

    @Test func sameDayOrderDoesNotDependOnInsertion() throws {
        func run(_ order: [Int]) throws -> MonthSummary {
            let f = try Fixture()
            try f.account("chk"); try f.account("visa", .creditCard); try f.category("groc")
            try f.assign("groc", "2026-01", 100)
            let lines: [(String, Double, String)] = [("a", -80, "chk"), ("b", -60, "visa")]
            for i in order { try f.tx(lines[i].2, "2026-01-04", lines[i].1, "groc", id: lines[i].0) }
            return try f.summary("2026-01")
        }
        #expect(try run([0, 1]) == run([1, 0]))
    }

    @Test func gapMonthsCarryAcrossEmptyMonths() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100)
        #expect(try f.summary("2026-06").categories["groc"]?.carryover == usd(100))
    }

    @Test func monthBeforeAnyDataIsZero() throws {
        let f = try setup()
        try f.income("chk", "2026-03-01", 100); try f.assign("groc", "2026-03", 40)
        let s = try f.summary("2025-06")
        #expect(s.categories.values.allSatisfy { $0.available == 0 })
        #expect(s.readyToAssign == -usd(40))      // assignments in every month, future ones included, come out of any month's RTA
    }

    @Test func hiddenCategoryAndClosedAccountStillCount() throws {
        let f = try Fixture()
        try f.account("old", closed: true); try f.category("quiet", hidden: true)
        try f.income("old", "2026-01-02", 100); try f.assign("quiet", "2026-01", 60); try f.tx("old", "2026-01-03", -10, "quiet")
        let s = try f.summary("2026-01")
        #expect(s.readyToAssign == usd(40) && s.categories["quiet"]?.available == usd(50))
    }
}

@Suite struct BudgetCardInflowTests {
    @Test func aRewardsCreditOnACardIsNotIncomeToAssign() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("visa", .creditCard)
        try f.income("chk", "2026-01-02", 100)
        try f.income("visa", "2026-01-03", 322)         // cash-back redemption on the card
        #expect(try f.summary("2026-01").readyToAssign == usd(100))
        #expect(try f.c.accountBalance(accountID: "visa").total == usd(322))
    }

    @Test func sameDayChargesCountLargerFirstSoTheCreditPartLandsOnTheSmallerLaterOne() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("a", .creditCard); try f.account("b", .creditCard); try f.category("fun")
        try f.assign("fun", "2026-01", 100)
        try f.tx("a", "2026-01-05", -90, "fun", id: "z1"); try f.tx("b", "2026-01-05", -30, "fun", id: "a1")     // 120 against 100 on one day
        let s = try f.summary("2026-01")
        #expect(s.categories["card-payment-a"]?.activity == usd(90) && s.categories["card-payment-b"]?.activity == usd(10))
    }
}
