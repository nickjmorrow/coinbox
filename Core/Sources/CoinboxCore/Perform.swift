import Foundation
import GRDB

public struct Change: Codable, Sendable, Equatable {
    public let id: Int64
    public let author: Author
    public let kind: String
    public let summary: String
    public let createdAt: Int64
    public let undone: Bool
    /// Its undo was attempted and skipped because a later edit by someone else touched the same things; it is still in effect.
    public let skipped: Bool
}

public struct UndoResult: Codable, Sendable, Equatable {
    public var undone: Int
    /// Changes whose undo was skipped because a later edit by someone else touched the same things, or their target is gone.
    public var skipped: [String]

    public init(undone: Int = 0, skipped: [String] = []) { self.undone = undone; self.skipped = skipped }
}

extension Coinbox {
    /// Applies `ops` in one transaction and logs them as a single change with its inverse.
    /// If any op throws, nothing is applied or logged. Returns the change id.
    @discardableResult
    public func perform(_ ops: [Op], author: Author) throws -> Int64 {
        try db.write { try log(ops, in: $0, author: author, undoes: nil) }
    }

    func log(_ ops: [Op], in db: Database, author: Author, undoes: Int64?) throws -> Int64 {
        guard !ops.isEmpty else { throw CoinboxError.invalid("no ops") }
        let op: Op = ops.count == 1 ? ops[0] : .batch(ops)
        let inverse = try Applier.apply(op, in: db)
        let ts = try nextTimestamp(db)
        for key in op.entityKeys { try Coinbox.setClock(key, ts: ts, device: device, db) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try db.execute(sql: """
            INSERT INTO ops (device, author, kind, payload, inverse, created_at, undoes, ts, origin_device, local, pushed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0)
            """, arguments: [device, author.rawValue, op.kind,
                              String(decoding: try encoder.encode(op), as: UTF8.self),
                              String(decoding: try encoder.encode(inverse), as: UTF8.self),
                              clock(), undoes, ts, device])
        let id = db.lastInsertedRowID
        try db.execute(sql: "UPDATE ops SET origin_id = ? WHERE local_id = ?", arguments: [id, id])
        return id
    }

    public func changes(since: Int64, author: Author? = nil) throws -> [Change] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT local_id, author, kind, payload, created_at, undone_by, voided FROM ops
                WHERE created_at >= ? AND (? IS NULL OR author = ?) ORDER BY local_id
                """, arguments: [since, author?.rawValue, author?.rawValue]).map { row in
                let op = try JSONDecoder().decode(Op.self, from: Data((row["payload"] as String).utf8))
                let undoneBy: Int64? = row["undone_by"]
                return Change(id: row["local_id"], author: Author(rawValue: row["author"]) ?? .importer, kind: row["kind"],
                              summary: op.summary, createdAt: row["created_at"], undone: undoneBy != nil,
                              skipped: row["voided"] as Bool)
            }
        }
    }

    /// Undoes the newest change (optionally only one author's) that hasn't been undone, by performing its stored inverse as a
    /// new change. If a later change by someone else touched the same entities, or the inverse cannot apply, nothing is
    /// reverted: that change is reported in `skipped`, stays in effect, and is not offered again, so the next call moves on
    /// to the one before it.
    @discardableResult
    public func undo(author: Author? = nil) throws -> UndoResult {
        try db.write { db in
            let decoder = JSONDecoder()
            guard let row = try Row.fetchOne(db, sql: """
                SELECT local_id, author, payload, inverse FROM ops
                WHERE inverse IS NOT NULL AND undone_by IS NULL AND undoes IS NULL AND voided = 0 AND (? IS NULL OR author = ?)
                ORDER BY local_id DESC LIMIT 1
                """, arguments: [author?.rawValue, author?.rawValue]) else { return UndoResult(undone: 0, skipped: []) }
            let id: Int64 = row["local_id"]
            let rowAuthor = Author(rawValue: row["author"]) ?? .importer
            let payload = try decoder.decode(Op.self, from: Data((row["payload"] as String).utf8))
            let inverse = try decoder.decode(Op.self, from: Data((row["inverse"] as String).utf8))
            let keys = payload.entityKeys.union(inverse.entityKeys)
            // Later changes by others that are still in effect (including skipped ones). A change counts by what it wrote and
            // by what it overwrote, so a merge that rewrote a routine blocks edits to that routine.
            let later = try Row.fetchAll(db, sql: """
                SELECT payload, inverse FROM ops
                WHERE local_id > ? AND undone_by IS NULL AND undoes IS NULL AND (author != ? OR local = 0)
                """, arguments: [id, rowAuthor.rawValue])
            let blocked = try later.contains { r in
                var touched = try decoder.decode(Op.self, from: Data((r["payload"] as String).utf8)).entityKeys
                if let inv: String = r["inverse"] { touched.formUnion(try decoder.decode(Op.self, from: Data(inv.utf8)).entityKeys) }
                return !touched.isDisjoint(with: keys)
            }
            func skip() throws -> UndoResult {
                try db.execute(sql: "UPDATE ops SET voided = 1 WHERE local_id = ?", arguments: [id])
                return UndoResult(undone: 0, skipped: [payload.summary])
            }
            if blocked { return try skip() }
            do {
                try db.inSavepoint {
                    let newID = try log([inverse], in: db, author: author ?? rowAuthor, undoes: id)
                    try db.execute(sql: "UPDATE ops SET undone_by = ? WHERE local_id = ?", arguments: [newID, id])
                    return .commit
                }
                return UndoResult(undone: 1, skipped: [])
            } catch is CoinboxError {
                return try skip()
            }
        }
    }
}

extension Coinbox {
    /// True when the newest change is an undo, so `redo` can put the undone change back.
    public func canRedo() throws -> Bool {
        try db.read { try Int64.fetchOne($0, sql: "SELECT undoes FROM ops WHERE local = 1 ORDER BY local_id DESC LIMIT 1") != nil }
    }

    /// Re-applies the change the newest undo took back (one step). Nil when the newest change isn't an undo.
    @discardableResult
    public func redo(author: Author) throws -> Int64? {
        let payload: String? = try db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT undoes FROM ops WHERE local = 1 ORDER BY local_id DESC LIMIT 1"), let original: Int64 = row["undoes"] else { return nil }
            return try String.fetchOne(db, sql: "SELECT payload FROM ops WHERE local_id = ?", arguments: [original])
        }
        guard let payload, let op = try? JSONDecoder().decode(Op.self, from: Data(payload.utf8)) else { return nil }
        return try perform([op], author: author)
    }
}
