import Testing
@testable import CoinboxCore

@Suite struct EntitySyncTests {
    private func seedCategory(_ w: World) async throws {
        try w.a.perform([.putCategoryGroup(CategoryGroup(id: "g", name: "G")), .putCategory(Category(id: "groc", groupID: "g", name: "Groc"))], author: .mac)
        try await w.sync(w.a); try await w.sync(w.b)
    }

    @Test func assignmentNewestWriteWinsEitherOrder() async throws {
        for bFirst in [false, true] {
            let w = try World()
            try await seedCategory(w)
            w.clockA.tick(1000); try w.a.perform([.putAssignment(Assignment(categoryID: "groc", month: "2026-01", amount: 100))], author: .mac)
            w.clockB.tick(5000); try w.b.perform([.putAssignment(Assignment(categoryID: "groc", month: "2026-01", amount: 200))], author: .mac)
            if bFirst { try await w.sync(w.b); try await w.sync(w.a) } else { try await w.sync(w.a); try await w.sync(w.b) }
            try await w.sync(w.a); try await w.sync(w.b)
            #expect(try w.a.assignment(categoryID: "groc", month: "2026-01")?.amount == 200)
            #expect(try w.b.assignment(categoryID: "groc", month: "2026-01")?.amount == 200)
        }
    }

    @Test func transactionWithSplitsReplicatesToHub() async throws {
        let w = try World()
        try w.a.perform([.putAccount(Account(id: "chk", name: "Chk")), .putCategoryGroup(CategoryGroup(id: "g", name: "G")),
                         .putCategory(Category(id: "groc", groupID: "g", name: "Groc")), .putCategory(Category(id: "fun", groupID: "g", name: "Fun"))], author: .mac)
        let t = Transaction(id: "t", accountID: "chk", date: "2026-01-02", amount: -50_000, splits: [SplitLine(categoryID: "groc", amount: -30_000), SplitLine(categoryID: "fun", amount: -20_000)])
        try w.a.perform([.putTransaction(t)], author: .mac)
        try await w.sync(w.a); try await w.sync(w.b)
        #expect(try w.hub.coinbox.transaction(id: "t") == t)
        #expect(try w.b.transaction(id: "t") == t)
    }

    @Test func cardCreationBatchReplicates() async throws {
        let w = try World()
        try w.a.perform(Coinbox.createAccountOps(Account(id: "visa", name: "Visa", kind: .creditCard)), author: .mac)
        try await w.sync(w.a); try await w.sync(w.b)
        #expect(try w.hub.coinbox.account(id: "visa") != nil && (try w.hub.coinbox.category(id: "card-payment-visa")) != nil)
        #expect(try w.b.account(id: "visa") != nil && (try w.b.category(id: "card-payment-visa")) != nil)
    }
}
