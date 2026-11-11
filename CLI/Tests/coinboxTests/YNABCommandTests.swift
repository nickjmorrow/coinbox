import Foundation
import Testing
import CoinboxCore
@testable import coinbox

@Suite(.serialized) struct YNABCommandTests {
    /// A tiny saved YNAB plan whose numbers are consistent with the budget rules.
    private func savedPlan() throws -> String {
        let dir = NSTemporaryDirectory() + "ynab-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func save(_ name: String, _ json: String) throws { try json.write(toFile: dir + "/\(name).json", atomically: true, encoding: .utf8) }
        try save("accounts", #"{"data":{"accounts":[{"id":"a1","name":"Checking","type":"checking","on_budget":true,"closed":false,"balance":1500000,"deleted":false}]}}"#)
        try save("payees", #"{"data":{"payees":[]}}"#)
        try save("categories", #"{"data":{"category_groups":[{"id":"gi","name":"Internal Master Category","categories":[{"id":"rta","category_group_id":"gi","name":"Inflow: Ready to Assign"}]},{"id":"gb","name":"Bills","categories":[{"id":"rent","category_group_id":"gb","name":"Rent"}]}]}}"#)
        try save("months", #"{"data":{"months":[{"month":"2026-01-01","to_be_budgeted":1300000}]}}"#)
        try save("month-2026-01-01", #"{"data":{"month":{"month":"2026-01-01","to_be_budgeted":1300000,"categories":[{"id":"rent","budgeted":200000,"activity":0,"balance":200000}]}}}"#)
        try save("transactions", #"{"data":{"transactions":[{"id":"t1","date":"2026-01-02","amount":1000000,"cleared":"cleared","approved":true,"account_id":"a1","category_id":"rta","deleted":false,"subtransactions":[]}]}}"#)
        return dir
    }

    @Test func dryRunWritesNothing() async throws {
        let db = tempDB(), dir = try savedPlan()
        let r = await Runner.run(["import-ynab", "--from-dir", dir, "--db", db])
        #expect(r.code == 0, Comment(rawValue: r.err))
        let out = try #require(try parse(r.out) as? [String: Any])
        #expect(out["applied"] as? Bool == false && (out["opsToApply"] as? Int ?? 0) > 0)
        #expect(try Coinbox.open(path: db, device: "t").accounts().isEmpty)
    }

    @Test func applyThenRerunIsEmptyAndCompareIsClean() async throws {
        let db = tempDB(), dir = try savedPlan()
        let first = await Runner.run(["import-ynab", "--from-dir", dir, "--apply", "--db", db])
        #expect(first.code == 0, Comment(rawValue: first.err))
        let again = try #require(try parse(await Runner.run(["import-ynab", "--from-dir", dir, "--apply", "--db", db]).out) as? [String: Any])
        #expect(again["opsToApply"] as? Int == 0)
        let compare = await Runner.run(["ynab-compare", "--from-dir", dir, "--db", db])
        let diffs = try #require(try parse(compare.out) as? [Any])
        #expect(diffs.isEmpty)
    }

    @Test func compareCommandPrintsDifferences() async throws {
        let db = tempDB(), dir = try savedPlan()
        _ = await Runner.run(["import-ynab", "--from-dir", dir, "--apply", "--db", db])
        let c = try Coinbox.open(path: db, device: "t")
        try c.perform([.putAssignment(Assignment(categoryID: "ynab-rent", month: "2026-01", amount: 250_000))], author: .mac)
        let r = try #require(try parse(await Runner.run(["ynab-compare", "--from-dir", dir, "--db", db]).out) as? [[String: Any]])
        #expect(r.contains { $0["subject"] as? String == "Rent: assigned" })
    }

    @Test func missingTokenIsAOneLineError() async throws {
        unsetenv("YNAB_TOKEN")
        let r = await Runner.run(["import-ynab", "--plan", "x", "--db", tempDB()])
        #expect(r.code == 1)
        #expect((try parse(r.err) as? [String: Any])?["error"] as? String == "set YNAB_TOKEN to a YNAB personal access token, or pass --from-dir")
    }
}
