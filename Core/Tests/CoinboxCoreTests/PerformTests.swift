import Foundation
import GRDB
import Testing
@testable import CoinboxCore

func opCount(_ f: Coinbox) throws -> Int { try f.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM ops")! } }

@Suite struct PerformTests {
    @Test func performLogsOneRowPerCall() throws {
        let f = try Coinbox.inMemory()
        try f.perform([.putMonthNote(note("a", "A")), .putMonthNote(note("b", "B")), .putMonthNote(note("c", "C"))], author: .mac)
        #expect(try opCount(f) == 1)
    }

    @Test func failedBatchAppliesNothing() throws {
        let f = try Coinbox.inMemory()
        #expect(throws: CoinboxError.notFound("monthNote nope")) {
            try f.perform([.putMonthNote(note("a", "A")), .deleteMonthNote(month: "nope")], author: .mac)
        }
        #expect(try f.monthNote("a") == nil)
        #expect(try opCount(f) == 0)
    }

    @Test func undoRestoresPreviousNote() throws {
        let f = try Coinbox.inMemory()
        try f.perform([.putMonthNote(note("r1", "Legs"))], author: .mac)
        try f.perform([.putMonthNote(note("r1", "Legs 2"))], author: .mac)
        let result = try f.undo(author: nil)
        #expect(result.undone == 1)
        #expect(try f.monthNote("r1")?.text == "Legs")
    }

    @Test func undoOfDeleteRestoresNote() throws {
        let f = try Coinbox.inMemory()
        try f.perform([.putMonthNote(note("r1", "Chest"))], author: .mac)
        try f.perform([.deleteMonthNote(month: "r1")], author: .claude)
        #expect(try f.monthNote("r1") == nil)
        _ = try f.undo(author: .claude)
        #expect(try f.monthNote("r1") == note("r1", "Chest"))
    }

    @Test func undoOnlyTouchesRequestedAuthor() throws {
        let f = try Coinbox.inMemory()
        try f.perform([.putMonthNote(note("r1", "A"))], author: .mac)
        try f.perform([.putMonthNote(note("r2", "C"))], author: .claude)
        let result = try f.undo(author: .claude)
        #expect(result.undone == 1)
        #expect(try f.monthNote("r2") == nil)
        #expect(try f.monthNote("r1") != nil)
    }

    @Test func undoSkipsWhenLaterEditTouchedSameEntity() throws {
        let f = try Coinbox.inMemory()
        try f.perform([.putMonthNote(note("r1", "Start"))], author: .mac)
        try f.perform([.putMonthNote(note("r1", "Claude title"))], author: .claude)
        try f.perform([.putMonthNote(note("r1", "My title"))], author: .mac)
        let result = try f.undo(author: .claude)
        #expect(result.undone == 0)
        #expect(result.skipped.count == 1)
        #expect(try f.monthNote("r1")?.text == "My title")
    }

    @Test func changesListsOpsWithUndoneFlag() throws {
        let f = try Coinbox.inMemory()
        try f.perform([.putMonthNote(note("2026-01", "Legs"))], author: .claude)
        _ = try f.undo(author: .claude)
        let changes = try f.changes(since: 0, author: .claude)
        #expect(changes.count == 2)
        #expect(changes[0].undone)
        #expect(changes[0].summary.contains("2026-01"))
    }
}

@Suite struct UndoSafetyTests {
    private func edit(_ f: Coinbox, _ text: String, _ author: Author) throws {
        try f.perform([.putMonthNote(note("r", text))], author: author)
    }

    @Test func skippedEditStillProtectsItsEntity() throws {
        let f = try Coinbox.inMemory()
        try edit(f, "v0", .mac)
        try edit(f, "claude1", .claude)
        try edit(f, "me2", .mac)
        try edit(f, "claude3", .claude)
        #expect(try f.undo(author: .mac).undone == 0)        // me2 is blocked by claude3
        #expect(try f.undo(author: .claude).undone == 1)    // claude3 undone -> me2
        #expect(try f.monthNote("r")?.text == "me2")
        let again = try f.undo(author: .claude)             // claude1 is blocked by me2, which is still applied
        #expect(again.undone == 0 && again.skipped.count == 1)
        #expect(try f.monthNote("r")?.text == "me2")
    }

    @Test func changesMarkSkippedAsSkippedNotUndone() throws {
        let f = try Coinbox.inMemory()
        try edit(f, "v0", .mac)
        try edit(f, "claude1", .claude)
        try edit(f, "me2", .mac)
        _ = try f.undo(author: .claude)
        let claude = try #require(try f.changes(since: 0, author: .claude).first)
        #expect(claude.skipped && !claude.undone)
        #expect(try f.monthNote("r")?.text == "me2")
    }

    @Test func undoStopsAtFirstBlockedChange() throws {
        let f = try Coinbox.inMemory()
        try f.perform([.putMonthNote(note("a", "A0")), .putMonthNote(note("b", "B0"))], author: .mac)
        try f.perform([.putMonthNote(note("a", "A1"))], author: .claude)
        try f.perform([.putMonthNote(note("b", "B1"))], author: .claude)
        try f.perform([.putMonthNote(note("b", "Bme"))], author: .mac)
        let first = try f.undo(author: .claude)
        #expect(first.undone == 0 && first.skipped.count == 1)
        #expect(try f.monthNote("a")?.text == "A1")      // the older, unrelated change was not touched
        #expect(try f.undo(author: .claude).undone == 1)    // a second call moves on to it
        #expect(try f.monthNote("a")?.text == "A0")
        #expect(try f.monthNote("b")?.text == "Bme")
    }
}
