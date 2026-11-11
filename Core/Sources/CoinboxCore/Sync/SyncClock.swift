import Foundation
import GRDB

/// The logical clock and per-entity clocks behind last-writer-wins sync.
extension Coinbox {
    /// A timestamp greater than anything this database has seen, so an edit made after receiving someone's work always beats it,
    /// even if this device's wall clock runs behind.
    func nextTimestamp(_ db: Database) throws -> Int64 {
        let last = try Int64.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'lamport'") ?? 0
        let ts = max(clock(), last + 1)
        try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('lamport', ?)", arguments: [String(ts)])
        return ts
    }

    static func observe(_ ts: Int64, _ db: Database) throws {
        let last = try Int64.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'lamport'") ?? 0
        if ts > last { try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('lamport', ?)", arguments: [String(ts)]) }
    }

    static func setClock(_ entity: String, ts: Int64, device: String, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO clocks (entity, ts, device) VALUES (?, ?, ?)", arguments: [entity, ts, device])
    }

    static func clock(of entity: String, _ db: Database) throws -> (ts: Int64, device: String)? {
        try Row.fetchOne(db, sql: "SELECT ts, device FROM clocks WHERE entity = ?", arguments: [entity]).map { ($0["ts"], $0["device"]) }
    }

    func meta(_ key: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) }
    }

    func setMeta(_ key: String, _ value: String) throws {
        try db.write { try $0.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key, value]) }
    }
}

extension Op {
    /// The op with batches flattened, in order.
    var leaves: [Op] {
        if case let .batch(ops) = self { return ops.flatMap(\.leaves) }
        return [self]
    }
}
