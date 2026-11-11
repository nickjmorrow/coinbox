import Testing
@testable import CoinboxCore

@Suite struct MonthNoteOpsTests {
    @Test func putMonthNoteIsLoggedAndReadable() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putMonthNote(MonthNote(month: "2026-01", text: "tight"))], author: .mac)
        #expect(try c.monthNote("2026-01")?.text == "tight")
    }

    @Test func undoRestoresPreviousNote() throws {
        let c = try Coinbox.inMemory()
        try c.perform([.putMonthNote(note("2026-01", "a"))], author: .mac)
        try c.perform([.putMonthNote(note("2026-01", "b"))], author: .mac)
        try c.undo()
        #expect(try c.monthNote("2026-01")?.text == "a")
        try c.undo()
        #expect(try c.monthNote("2026-01") == nil)
    }

    @Test func deleteMissingNoteThrowsNotFound() throws {
        let c = try Coinbox.inMemory()
        #expect(throws: CoinboxError.notFound("monthNote 2026-02")) {
            try c.perform([.deleteMonthNote(month: "2026-02")], author: .claude)
        }
    }

    @Test func importAuthorRawValue() {
        #expect(Author.importer.rawValue == "import")
    }
}
