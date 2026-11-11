import Testing
@testable import CoinboxCore

@Suite struct BudgetCardTests {
    private let P = "card-payment-card"

    private func setup() throws -> Fixture {
        let f = try Fixture()
        try f.account("chk"); try f.account("card", .creditCard); try f.category("groc")
        return f
    }

    private func jan(_ f: Fixture) throws -> MonthSummary { try f.summary("2026-01") }

    @Test func cardSpendMovesCoveredPartToPaymentCategory() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 200); try f.tx("card", "2026-01-05", -120, "groc")
        let s = try jan(f)
        #expect(s.categories["groc"]?.available == usd(80))
        #expect(s.categories[P]?.activity == usd(120) && s.categories[P]?.available == usd(120))
    }

    @Test func uncoveredPartIsNotMoved() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("card", "2026-01-05", -150, "groc")
        let s = try jan(f)
        #expect(s.categories[P]?.activity == usd(100) && s.categories["groc"]?.available == usd(-50))
    }

    @Test func spendWithPartialCoverage() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("chk", "2026-01-02", -70, "groc"); try f.tx("card", "2026-01-05", -50, "groc")
        #expect(try jan(f).categories[P]?.activity == usd(30))
    }

    @Test func paymentIsOutflowOnPaymentCategory() throws {
        let f = try setup()
        try f.income("chk", "2026-01-01", 1000)
        try f.assign("groc", "2026-01", 200); try f.tx("card", "2026-01-05", -120, "groc")
        let before = try jan(f).readyToAssign
        try f.transfer("chk", "card", "2026-01-20", 120)
        let s = try jan(f)
        #expect(s.categories[P]?.activity == 0 && s.categories[P]?.available == 0)
        #expect(s.readyToAssign == before)
    }

    @Test func refundReversesMove() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 200); try f.tx("card", "2026-01-05", -120, "groc"); try f.tx("card", "2026-01-08", 20, "groc")
        let s = try jan(f)
        #expect(s.categories["groc"]?.available == usd(100) && s.categories[P]?.available == usd(100))
    }

    @Test func refundOnOverspentCategoryOnlyHealsIt() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("card", "2026-01-05", -150, "groc"); try f.tx("card", "2026-01-08", 30, "groc")
        let s = try jan(f)
        #expect(s.categories["groc"]?.available == usd(-20) && s.categories[P]?.available == usd(100))
    }

    @Test func refundCrossingZeroMovesOnlyTheExcess() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 100); try f.tx("card", "2026-01-05", -150, "groc"); try f.tx("card", "2026-01-08", 80, "groc")
        let s = try jan(f)
        #expect(s.categories["groc"]?.available == usd(30) && s.categories[P]?.available == usd(70))
    }

    @Test func refundWithNoPriorPurchaseGoesNegativeOnPayment() throws {
        let f = try setup()
        try f.tx("card", "2026-01-08", 20, "groc")
        let s = try jan(f)
        #expect(s.categories["groc"]?.available == usd(20) && s.categories[P]?.available == usd(-20))
        #expect(s.categories[P]?.cashOverspent == usd(20))
    }

    @Test func negativeTransferLegOnCardIsIgnored() throws {
        let f = try setup()
        try f.transfer("card", "chk", "2026-01-08", 50)       // a cash advance
        #expect(try jan(f).categories[P]?.activity == 0)
    }

    @Test func interestChargeDoesNotMoveOrOverspend() throws {
        let f = try setup()
        try f.income("chk", "2026-01-01", 100)
        try f.tx("card", "2026-01-31", -20, "card-interest")
        let s = try jan(f)
        let i = try #require(s.categories["card-interest"])
        #expect(i.activity == usd(-20) && i.available == 0 && i.cashOverspent == 0 && i.creditOverspent == 0)
        #expect(s.categories[P]?.activity == 0 && s.readyToAssign == usd(100) && s.cashOverspending == 0)
    }

    @Test func startingDebtIsNotFunded() throws {
        let f = try setup()
        try f.tx("card", "2025-12-31", -500)
        let s = try f.summary("2026-01")
        #expect(s.categories[P]?.activity == 0 && s.categories[P]?.underfunded == usd(500))
    }

    @Test func carryoverOfPaymentCategory() throws {
        let f = try setup()
        try f.assign("groc", "2026-01", 200); try f.tx("card", "2026-01-05", -120, "groc")
        #expect(try f.summary("2026-02").categories[P]?.carryover == usd(120))
    }
}

@Suite struct BudgetCardOrderTests {
    @Test func cardThenCashSpendingMovesNothingThatCashOverspent() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("visa", .creditCard); try f.category("groc")
        try f.assign("groc", "2026-01", 100); try f.tx("visa", "2026-01-03", -30, "groc"); try f.tx("chk", "2026-01-04", -120, "groc")
        let s = try f.summary("2026-01")
        #expect(s.categories["groc"]?.creditOverspent == usd(30) && s.categories["groc"]?.cashOverspent == usd(20))
        #expect(s.categories["card-payment-visa"]?.activity == 0)        // the card spend is the overspent part, however the month's order ran
    }

    @Test func creditOverspendingIsTakenFromTheNewestCardChargesFirst() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("a", .creditCard); try f.account("b", .creditCard); try f.category("fun")
        try f.assign("fun", "2026-01", 100)
        try f.tx("a", "2026-01-02", -60, "fun"); try f.tx("b", "2026-01-10", -70, "fun")      // 130 against 100: 30 is overspent, on b's later charge
        let s = try f.summary("2026-01")
        #expect(s.categories["fun"]?.creditOverspent == usd(30))
        #expect(s.categories["card-payment-a"]?.activity == usd(60) && s.categories["card-payment-b"]?.activity == usd(40))
    }
}

@Suite struct BudgetCardRefundTests {
    @Test func aRefundOnAnotherCardHealsOverspendingWithoutPullingFromItsPaymentCategory() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("a", .creditCard); try f.account("b", .creditCard); try f.category("arts")
        try f.tx("a", "2026-01-08", -115.16, "arts"); try f.tx("a", "2026-01-10", -52.52, "arts"); try f.tx("b", "2026-01-20", 96.02, "arts")
        let s = try f.summary("2026-01")
        #expect(s.categories["arts"]?.available == usd(-71.66) && s.categories["arts"]?.creditOverspent == usd(71.66))
        #expect(s.categories["card-payment-a"]?.activity == 0 && s.categories["card-payment-b"]?.activity == 0)
    }
}
