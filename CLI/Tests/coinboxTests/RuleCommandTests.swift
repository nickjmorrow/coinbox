import Foundation
import Testing
import CoinboxCore
@testable import coinbox

private func opCount(_ c: Coinbox) throws -> Int { try c.changes(since: 0).count }

@Suite struct RuleCommandTests {
    private func run(_ args: [String], _ db: String) async -> RunResult { await Runner.run(args + ["--db", db]) }

    private func seed(_ db: String) async throws {
        _ = await run(["account", "put", "--json", #"{"id":"chk","name":"Checking"}"#], db)
        _ = await run(["account", "put", "--json", #"{"id":"sav","name":"Savings","kind":"savings"}"#], db)
        _ = await run(["category-group", "put", "--json", #"{"id":"g","name":"G"}"#], db)
        for id in ["fun", "fees"] { _ = await run(["category", "put", "--json", #"{"id":"\#(id)","groupID":"g","name":"\#(id)"}"#], db) }
        let c = try Coinbox.open(path: db, device: "t")
        for (id, raw, amt) in [("a", "VINYL SHOP", -10_000), ("b", "CARD INTEREST CHARGE VINYL", -2_000)] {
            try c.perform([.putTransaction(Transaction(id: id, accountID: "chk", date: "2026-01-05", amount: Milliunits(amt), approved: false, rawPayee: raw, author: .bank))], author: .bank)
        }
    }

    private let rules = #"[{"id":"i","name":"Interest","payee":{"mode":"contains","text":"interest"},"actions":{"categoryID":"fees","approve":true}},{"id":"w","name":"Vinyl","payee":{"mode":"contains","text":"vinyl"},"actions":{"categoryID":"fun","approve":true}}]"#

    @Test func putManyKeepsArrayOrder() async throws {
        let db = tempDB()
        #expect(await run(["rule", "put-many", "--json", rules], db).code == 0)
        let list = try #require(try parse(await run(["rule", "list"], db).out) as? [[String: Any]])
        #expect(list.map { $0["id"] as? String } == ["i", "w"] && list.map { $0["order"] as? Int } == [0, 1])
        _ = await run(["rule", "put-many", "--replace", "--json", #"[{"id":"w","name":"Vinyl","actions":{"categoryID":"fun"}}]"#], db)
        #expect(try #require(try parse(await run(["rule", "list"], db).out) as? [Any]).count == 1)
    }

    @Test func previewWritesNothingAndApplyIsOneUndoableChange() async throws {
        let db = tempDB()
        try await seed(db)
        _ = await run(["rule", "put-many", "--json", rules], db)
        let c = try Coinbox.open(path: db, device: "t")
        let before = try opCount(c)
        let preview = try #require(try parse(await run(["rule", "apply", "--preview"], db).out) as? [String: Any])
        #expect(preview["preview"] as? Bool == true && (preview["changes"] as? [Any])?.count == 2)
        #expect(try opCount(c) == before)
        #expect(await run(["rule", "apply"], db).code == 0)
        #expect(try opCount(c) == before + 1)
        #expect(try c.transaction(id: "b")?.categoryID == "fees" && (try c.transaction(id: "a")?.categoryID) == "fun" && (try c.transaction(id: "a")?.approved) == true)
        _ = await run(["undo"], db)
        #expect(try c.transaction(id: "a")?.approved == false)
    }

    @Test func badRegexIsReported() async throws {
        let db = tempDB()
        try await seed(db)
        _ = await run(["rule", "put", "--json", #"{"id":"x","name":"Broken","payee":{"mode":"regex","text":"(["},"actions":{"categoryID":"fun"}}"#], db)
        let out = try #require(try parse(await run(["rule", "apply", "--preview"], db).out) as? [String: Any])
        #expect(out["brokenRules"] as? [String] == ["Broken"])
    }

    @Test func approveOfATransferLegApprovesBoth() async throws {
        let db = tempDB()
        try await seed(db)
        let c = try Coinbox.open(path: db, device: "t")
        try c.perform(try c.transferOps(id: "x", date: "2026-01-06", from: "chk", to: "sav", amount: 5_000, author: .bank), author: .bank)
        for var t in try c.transactions() where t.transferPairID != nil { t.approved = false; try c.perform([.putTransaction(t)], author: .bank) }
        let r = await run(["transaction", "approve", "x-out"], db)
        #expect(r.code == 0)
        #expect(try c.transaction(id: "x-in")?.approved == true)
    }

    @Test func categorizeApproveAndDeleteMany() async throws {
        let db = tempDB()
        try await seed(db)
        let c = try Coinbox.open(path: db, device: "t")
        #expect(await run(["transaction", "categorize", "--category", "fun", "--approve", "a", "b"], db).code == 0)
        #expect(try c.transaction(id: "b")?.categoryID == "fun" && (try c.transaction(id: "b")?.approved) == true)
        #expect(await run(["transaction", "delete-many", "--preview", "a"], db).code == 0)
        #expect(try c.transaction(id: "a") != nil)
        #expect(await run(["transaction", "delete-many", "a", "b"], db).code == 0)
        #expect(try c.transactions(accountID: "chk").isEmpty)
    }

    @Test func schemaListsTransactionColumns() async throws {
        let db = tempDB()
        let tables = try #require(try parse(await run(["schema"], db).out) as? [[String: Any]])
        let tx = try #require(tables.first { $0["table"] as? String == "transactions" })
        #expect((tx["columns"] as? [[String: Any]])?.contains { $0["name"] as? String == "raw_payee" } == true)
        #expect(!tables.contains { $0["table"] as? String == "ops" })
    }

    @Test func shortTransactionJSONGetsTheCliAuthor() async throws {
        let db = tempDB()
        _ = await run(["account", "put", "--json", #"{"id":"chk","name":"Checking"}"#], db)
        let r = try #require(try parse(await run(["transaction", "put", "--json", #"{"id":"t","accountID":"chk","date":"2026-01-02","amount":-5000}"#], db).out) as? [String: Any])
        #expect(r["author"] as? String == "claude" && r["approved"] as? Bool == true)
    }
}
