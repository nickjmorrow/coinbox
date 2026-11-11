import Foundation
import Testing
@testable import CoinboxCore

private func seeded() throws -> Coinbox {
    let f = try Coinbox.inMemory()
    try f.perform([.putMonthNote(note("a", "A")), .putMonthNote(note("b", "B")), .putMonthNote(note("c", "C"))], author: .mac)
    return f
}

private func noteCount(_ f: Coinbox) throws -> Int { try f.monthNotes().count }

@Suite struct ReadOnlySQLTests {
    @Test func selectReturnsOrderedColumnsAndRows() throws {
        let f = try seeded()
        let result = try f.query(sql: "select month, text from month_notes order by text")
        #expect(result.columns == ["month", "text"])
        #expect(result.rows == [[.text("a"), .text("A")], [.text("b"), .text("B")], [.text("c"), .text("C")]])
    }

    @Test func valuesKeepTheirTypes() throws {
        let f = try Coinbox.inMemory()
        #expect(try f.query(sql: "select 1 as a, 2.5 as b, null as c, 'x' as d").rows == [[.int(1), .double(2.5), .null, .text("x")]])
    }

    @Test func insertRejectedAndTableUnchanged() throws {
        let f = try seeded()
        #expect(throws: CoinboxError.self) { try f.query(sql: "insert into month_notes (month, text) values ('2026-01', 'x')") }
        #expect(try f.db.read { try Int.fetchOne($0, sql: "select count(*) from month_notes") } == 3)
    }

    @Test func deleteRejected() throws {
        let f = try seeded()
        #expect(throws: CoinboxError.self) { try f.query(sql: "delete from month_notes") }
        #expect(try noteCount(f) == 3)
    }

    @Test func cteWrappedDeleteRejected() throws {
        let f = try seeded()
        #expect(throws: CoinboxError.self) { try f.query(sql: "with x as (select 1) delete from month_notes") }
        #expect(try noteCount(f) == 3)
    }

    @Test func pragmaWriteRejected() throws {
        let f = try seeded()
        #expect(throws: CoinboxError.self) { try f.query(sql: "pragma user_version = 7") }
        #expect(try f.db.read { try Int.fetchOne($0, sql: "pragma user_version") } == 0)
    }

    @Test func multiStatementRejected() throws {
        let f = try seeded()
        #expect(throws: CoinboxError.self) { try f.query(sql: "select 1; delete from month_notes") }
        #expect(try noteCount(f) == 3)
    }

    @Test func limitCapsRows() throws {
        let f = try seeded()
        #expect(try f.query(sql: "select month from month_notes", limit: 2).rows.count == 2)
    }
}
