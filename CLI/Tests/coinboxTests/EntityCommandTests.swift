import Foundation
import Testing
import CoinboxCore
@testable import coinbox

func parse(_ s: String) throws -> Any { try JSONSerialization.jsonObject(with: Data(s.utf8)) }

@Suite struct EntityCommandTests {
    private func run(_ args: [String], _ db: String) async -> RunResult { await Runner.run(args + ["--db", db]) }

    @Test func accountPutListGet() async throws {
        let db = tempDB()
        let put = await run(["account", "put", "--json", #"{"id":"chk","name":"Checking","kind":"checking","onBudget":true,"closed":false}"#], db)
        #expect(put.code == 0)
        let list = try #require(try parse(await run(["account", "list"], db).out) as? [[String: Any]])
        #expect(list.count == 1 && list[0]["name"] as? String == "Checking")
        let get = try #require(try parse(await run(["account", "get", "chk"], db).out) as? [String: Any])
        #expect(get["id"] as? String == "chk")
        #expect(await run(["account", "get", "nope"], db).code == 1)
    }

    @Test func creditCardPutCreatesPaymentCategory() async throws {
        let db = tempDB()
        _ = await run(["account", "put", "--json", #"{"id":"visa","name":"Visa","kind":"creditCard","onBudget":true,"closed":false}"#], db)
        let cat = try #require(try parse(await run(["category", "get", "card-payment-visa"], db).out) as? [String: Any])
        #expect(cat["name"] as? String == "Visa")
    }

    @Test func assignThenPlanShowsAssigned() async throws {
        let db = tempDB()
        _ = await run(["category-group", "put", "--json", #"{"id":"g","name":"Bills","order":0,"hidden":false}"#], db)
        _ = await run(["category", "put", "--json", #"{"id":"rent","groupID":"g","name":"Rent","order":0,"hidden":false,"kind":{"type":"normal"}}"#], db)
        let assign = await run(["assign", "rent", "2026-01", "1,200.50"], db)
        #expect(assign.code == 0, Comment(rawValue: assign.err))
        let plan = try #require(try parse(await run(["plan", "2026-01"], db).out) as? [String: Any])
        let groups = try #require(plan["groups"] as? [[String: Any]])
        let rows = try #require(groups.first { $0["name"] as? String == "Bills" }?["categories"] as? [[String: Any]])
        #expect(rows.first?["assigned"] as? Int == 1_200_500)
        #expect(plan["readyToAssignDisplay"] as? String == "-$1,200.50")
    }

    @Test func moveIsOneUndoableChange() async throws {
        let db = tempDB()
        _ = await run(["category-group", "put", "--json", #"{"id":"g","name":"G","order":0,"hidden":false}"#], db)
        for id in ["a", "b"] { _ = await run(["category", "put", "--json", #"{"id":"\#(id)","groupID":"g","name":"\#(id)","order":0,"hidden":false,"kind":{"type":"normal"}}"#], db) }
        _ = await run(["assign", "a", "2026-01", "100"], db)
        let before = try #require(try parse(await run(["changes"], db).out) as? [[String: Any]]).count
        #expect(await run(["move", "a", "b", "2026-01", "30"], db).code == 0)
        #expect(try #require(try parse(await run(["changes"], db).out) as? [[String: Any]]).count == before + 1)
        #expect(await run(["undo"], db).code == 0)
        let c = try Coinbox.open(path: db, device: "t")
        #expect(try c.assignment(categoryID: "a", month: "2026-01")?.amount == 100_000)
        #expect(try c.assignment(categoryID: "b", month: "2026-01") == nil)
    }

    @Test func transactionPutRejectsOutflowToRTA() async throws {
        let db = tempDB()
        _ = await run(["account", "put", "--json", #"{"id":"chk","name":"Checking","kind":"checking","onBudget":true,"closed":false}"#], db)
        let r = await run(["transaction", "put", "--json",
            #"{"id":"t","accountID":"chk","date":"2026-01-02","categoryID":"ready-to-assign","amount":-5000,"cleared":"uncleared","approved":true,"pending":false,"author":"claude","splits":[]}"#], db)
        #expect(r.code == 1)
        #expect((try parse(r.err) as? [String: Any])?["error"] as? String == "an outflow can't be categorized to Ready to Assign")
    }

    @Test func badAmountIsAnError() async throws {
        let r = await run(["assign", "x", "2026-01", "lots"], tempDB())
        #expect(r.code == 1)
    }

    @Test func parseDollarsIsExact() throws {
        #expect(try parseDollars("12.34") == 12_340)
        #expect(try parseDollars("-0.005") == -5)
        #expect(try parseDollars("$1,000") == 1_000_000)
    }
}
