import Testing
@testable import CoinboxCore

@Suite struct BuildersTests {
    @Test func cardAccountCreatesPaymentCategory() throws {
        let f = try Fixture()
        try f.account("visa", .creditCard)
        let p = try #require(try f.c.category(id: "card-payment-visa"))
        #expect(p.kind == .cardPayment(accountID: "visa") && p.name == "visa" && p.groupID == "card-payments")
    }

    @Test func nonCardHasNoPaymentCategory() throws {
        let f = try Fixture()
        try f.account("chk")
        #expect(try f.c.category(id: "card-payment-chk") == nil)
    }

    @Test func undoOfCardCreationRemovesBoth() throws {
        let f = try Fixture()
        try f.account("visa", .creditCard)
        try f.c.undo()
        #expect(try f.c.account(id: "visa") == nil && (try f.c.category(id: "card-payment-visa")) == nil)
    }

    @Test func transferBetweenOnBudgetHasNoCategory() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("sav", .savings)
        try f.transfer("chk", "sav", "2026-01-05", 500)
        let out = try #require(try f.c.transactions(accountID: "chk").first), inn = try #require(try f.c.transactions(accountID: "sav").first)
        #expect(out.amount == usd(-500) && inn.amount == usd(500))
        #expect(out.transferPairID == inn.id && inn.transferPairID == out.id)
        #expect(out.categoryID == nil && inn.categoryID == nil)
    }

    @Test func transferBetweenOnBudgetWithCategoryIsInvalid() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("sav", .savings); try f.category("groc")
        #expect(throws: CoinboxError.self) { try f.transfer("chk", "sav", "2026-01-05", 5, category: "groc") }
    }

    @Test func transferToTrackingNeedsCategory() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("mort", .mortgage)
        #expect(throws: CoinboxError.self) { try f.transfer("chk", "mort", "2026-01-05", 5) }
    }

    @Test func transferToTrackingCategoryOnlyOnBudgetLeg() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("mort", .mortgage); try f.category("Mortgage")
        try f.transfer("chk", "mort", "2026-01-05", 1000, category: "Mortgage")
        #expect(try f.c.transactions(accountID: "chk").first?.categoryID == "Mortgage")
        #expect(try f.c.transactions(accountID: "mort").first?.categoryID == nil)
    }

    @Test func transferZeroAmountInvalid() throws {
        let f = try Fixture()
        try f.account("chk"); try f.account("sav", .savings)
        #expect(throws: CoinboxError.self) { try f.transfer("chk", "sav", "2026-01-05", 0) }
    }

    @Test func transferBetweenTwoTrackingAccountsInvalid() throws {
        let f = try Fixture()
        try f.account("m", .mortgage); try f.account("l", .loan)
        #expect(throws: CoinboxError.self) { try f.transfer("m", "l", "2026-01-05", 5) }
    }
}
