import Foundation
import GRDB

/// Row-level reads and whole-aggregate writes.
enum Store {
    static func monthNote(_ month: String, _ db: Database) throws -> MonthNote? {
        try Row.fetchOne(db, sql: "SELECT * FROM month_notes WHERE month = ?", arguments: [month]).map { MonthNote(month: $0["month"], text: $0["text"]) }
    }

    static func writeMonthNote(_ n: MonthNote, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO month_notes (month, text) VALUES (?, ?)", arguments: [n.month, n.text])
    }
}

extension Coinbox {
    public func monthNote(_ month: String) throws -> MonthNote? { try db.read { try Store.monthNote(month, $0) } }
    public func monthNotes() throws -> [MonthNote] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM month_notes ORDER BY month").map { MonthNote(month: $0["month"], text: $0["text"]) } }
    }
}
