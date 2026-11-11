import Foundation
import Testing
import CoinboxCore
@testable import coinbox

@Suite struct PlanningCommandTests {
    private func run(_ args: [String], _ db: String) async -> RunResult { await Runner.run(args + ["--db", db]) }

    private func seed(_ db: String) async {
        _ = await run(["account", "put", "--json", #"{"id":"chk","name":"Checking"}"#], db)
        _ = await run(["category-group", "put", "--json", #"{"id":"g","name":"G"}"#], db)
        _ = await run(["category", "put", "--json", #"{"id":"rent","groupID":"g","name":"Rent"}"#], db)
        _ = await run(["target", "put", "--json", #"{"categoryID":"rent","amount":600000,"cadence":{"type":"monthly","day":1}}"#], db)
        _ = await run(["transaction", "put", "--json", #"{"id":"in","accountID":"chk","date":"2026-01-01","amount":1000000,"categoryID":"ready-to-assign","cleared":"cleared"}"#], db)
    }

    @Test func autoAssignPreviewThenApply() async throws {
        let db = tempDB()
        await seed(db)
        let preview = try #require(try parse(await run(["auto-assign", "--preview", "2026-01"], db).out) as? [String: Any])
        #expect(preview["assigned"] as? Int == 600_000 && preview["preview"] as? Bool == true)
        #expect(try Coinbox.open(path: db, device: "t").assignments().isEmpty)
        #expect(await run(["auto-assign", "2026-01"], db).code == 0)
        #expect(try Coinbox.open(path: db, device: "t").assignment(categoryID: "rent", month: "2026-01")?.amount == 600_000)
    }

    @Test func runwayAndMoneyMoves() async throws {
        let db = tempDB()
        await seed(db)
        _ = await run(["assign", "rent", "2026-01", "600"], db)
        let runway = try #require(try parse(await run(["runway", "--month", "2026-01"], db).out) as? [String: Any])
        #expect(runway["cash"] as? Int == 1_000_000 && runway["months"] as? Double == 1.7)
        let moves = try #require(try parse(await run(["money-moves", "2026-01"], db).out) as? [[String: Any]])
        #expect(moves.count == 1 && moves[0]["author"] as? String == "claude")
    }

    @Test func reconcileNeedsAdjustForADifference() async throws {
        let db = tempDB()
        await seed(db)
        #expect(await run(["reconcile", "chk", "--date", "2026-01-31", "--balance", "999.00"], db).code == 1)
        #expect(await run(["reconcile", "chk", "--date", "2026-01-31", "--balance", "999.00", "--adjust"], db).code == 0)
        #expect(try Coinbox.open(path: db, device: "t").account(id: "chk")?.lastReconciledBalance == 999_000)
    }

    @Test func searchFindsByText() async throws {
        let db = tempDB()
        await seed(db)
        _ = await run(["transaction", "put", "--json", #"{"id":"x","accountID":"chk","date":"2026-01-03","amount":-5000,"rawPayee":"CORNER BAKERY"}"#], db)
        let r = try #require(try parse(await run(["transaction", "search", "--text", "bakery"], db).out) as? [[String: Any]])
        #expect(r.map { $0["id"] as? String } == ["x"])
    }
}
