import Foundation
import Testing
import CoinboxCore
@testable import coinbox

@Suite struct SimpleFINCommandTests {
    private func run(_ args: [String], _ db: String) async -> RunResult { await Runner.run(args + ["--db", db]) }

    private func savedResponse() throws -> String {
        let path = NSTemporaryDirectory() + "sf-\(UUID().uuidString).json"
        try #"{"accounts":[{"id":"ACT-1","name":"Checking","balance":"100.00","org":{"name":"Bank"},"transactions":[{"id":"T1","posted":1767614400,"amount":"-12.34","description":"COFFEE SHOP"},{"id":"T2","posted":1767614400,"amount":"-3.00","description":"PENDING THING","pending":true}]}]}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test func linkPreviewApplyAndRepeat() async throws {
        let db = tempDB(), file = try savedResponse()
        _ = await run(["account", "put", "--json", #"{"id":"chk","name":"Checking"}"#], db)
        #expect(await run(["simplefin-link", "ACT-1", "chk"], db).code == 0)
        let preview = try #require(try parse(await run(["simplefin-sync", "--from-file", file, "--preview", "--timezone", "UTC"], db).out) as? [String: Any])
        #expect(preview["newTransactions"] as? Int == 1 && preview["skippedPending"] as? Int == 1)
        #expect(try Coinbox.open(path: db, device: "t").transactions().isEmpty)
        let applied = try #require(try parse(await run(["simplefin-sync", "--from-file", file, "--timezone", "UTC"], db).out) as? [String: Any])
        #expect(applied["newTransactions"] as? Int == 1)
        let again = try #require(try parse(await run(["simplefin-sync", "--from-file", file, "--timezone", "UTC"], db).out) as? [String: Any])
        #expect(again["newTransactions"] as? Int == 0)
        let c = try Coinbox.open(path: db, device: "t")
        #expect(try c.transactions().first?.rawPayee == "COFFEE SHOP" && (try c.transactions().first?.approved) == false)
    }

    @Test func accountsListShowsLinks() async throws {
        let db = tempDB(), file = try savedResponse()
        _ = await run(["account", "put", "--json", #"{"id":"chk","name":"Checking"}"#], db)
        _ = await run(["simplefin-link", "ACT-1", "chk"], db)
        let rows = try #require(try parse(await run(["simplefin-accounts", "--from-file", file], db).out) as? [[String: Any]])
        #expect(rows.count == 1 && rows[0]["simplefinID"] as? String == "ACT-1" && rows[0]["bank"] as? String == "Bank" && rows[0]["linkedTo"] as? String == "Checking")
    }

    @Test func linkingAnUnknownAccountFails() async throws {
        #expect(await run(["simplefin-link", "ACT-1", "nope"], tempDB()).code == 1)
    }

    @Test func missingAccessFileNamesThePathNotTheSecret() async throws {
        let r = await run(["simplefin-sync", "--access-file", "/tmp/definitely-not-here-\(UUID().uuidString)"], tempDB())
        #expect(r.code == 1)
        let message = try #require((try parse(r.err) as? [String: Any])?["error"] as? String)
        #expect(message.contains("no SimpleFIN access URL at /tmp/definitely-not-here"))
    }

    @Test func aBadAccessFileDoesNotEchoItsContents() async throws {
        let path = NSTemporaryDirectory() + "access-\(UUID().uuidString)"
        try "https://alice:s3cret".write(toFile: path, atomically: true, encoding: .utf8)
        let r = await run(["simplefin-sync", "--access-file", path], tempDB())
        #expect(r.code == 1 && !r.err.contains("s3cret") && !r.out.contains("s3cret"))
    }

    @Test func claimWithGarbageIsAOneLineError() async throws {
        let r = await Runner.run(["simplefin-claim", "--token", "nonsense!!", "--access-file", NSTemporaryDirectory() + "never"])
        #expect(r.code == 1)
        #expect((try parse(r.err) as? [String: Any])?["error"] as? String == "that doesn't look like a SimpleFIN setup token")
    }
}
