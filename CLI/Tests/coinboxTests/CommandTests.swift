import Foundation
import Testing
import CoinboxCore
@testable import coinbox

func tempDB() -> String {
    NSTemporaryDirectory() + "coinbox-test-\(UUID().uuidString)/coinbox.sqlite"
}

private func json(_ s: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
}

@Suite struct CommandTests {
    @Test func monthNoteSetThenGet() async throws {
        let path = tempDB()
        let set = await Runner.run(["month-note", "set", "2026-01", "tight month", "--db", path])
        #expect(set.code == 0)
        let get = await Runner.run(["month-note", "get", "2026-01", "--db", path])
        #expect(get.code == 0)
        #expect(try json(get.out)["text"] as? String == "tight month")
    }

    @Test func changesListsTheSet() async throws {
        let path = tempDB()
        _ = await Runner.run(["month-note", "set", "2026-01", "x", "--db", path])
        let r = await Runner.run(["changes", "--db", path])
        let rows = try #require(JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["author"] as? String == "claude")
        #expect((rows[0]["summary"] as? String)?.contains("2026-01") == true)
    }

    @Test func undoRevertsLastClaudeChange() async throws {
        let path = tempDB()
        _ = await Runner.run(["month-note", "set", "2026-01", "x", "--db", path])
        let undo = await Runner.run(["undo", "--db", path])
        #expect(undo.code == 0)
        #expect(try json(undo.out)["undone"] as? Int == 1)
        let get = await Runner.run(["month-note", "get", "2026-01", "--db", path])
        #expect(get.code == 1)
    }

    @Test func sqlRejectsWrites() async throws {
        let path = tempDB()
        _ = await Runner.run(["month-note", "set", "2026-01", "x", "--db", path])
        let r = await Runner.run(["sql", "DELETE FROM month_notes", "--db", path])
        #expect(r.code == 1)
        #expect(r.out.isEmpty)
        #expect(try json(r.err)["error"] != nil)
    }

    @Test func badMonthIsAnError() async throws {
        let r = await Runner.run(["month-note", "get", "2026-13", "--db", tempDB()])
        #expect(r.code == 1)
        #expect(try (json(r.err)["error"] as? String)?.contains("2026-01") == true)
    }
}
