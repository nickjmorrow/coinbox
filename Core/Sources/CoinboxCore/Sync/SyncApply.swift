import Foundation
import GRDB

extension Coinbox {
    /// Local changes that haven't been sent to the hub, oldest first.
    public func outgoingOps() throws -> [OutgoingOp] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT local_id, author, payload, created_at, ts FROM ops WHERE local = 1 AND pushed = 0 ORDER BY local_id").map {
                OutgoingOp(localID: $0["local_id"], author: $0["author"], payload: $0["payload"], createdAt: $0["created_at"], ts: $0["ts"])
            }
        }
    }

    func markPushed(_ assigned: [SeqAssignment]) throws {
        try db.write { db in
            for a in assigned {
                try db.execute(sql: "UPDATE ops SET pushed = 1, seq = ? WHERE local_id = ? AND local = 1", arguments: [a.seq, a.localID])
            }
        }
    }

    /// Applies a pulled batch (skipping changes this device made itself) and remembers how far it got, all in one transaction.
    func applyPulled(_ batch: [RemoteOp]) throws -> (applied: Int, failed: Int) {
        try db.write { db in
            var applied = 0, failed = 0
            for r in batch where r.originDevice != device {
                switch try Coinbox.applyRemote(r, in: db) {
                case .applied: applied += 1
                case .failed: failed += 1
                case .ignored: break
                }
            }
            if let last = batch.last {
                try db.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('pulled_seq', ?)", arguments: [String(last.seq)])
            }
            return (applied, failed)
        }
    }

    enum RemoteResult { case applied, ignored, failed }

    /// Applies a change that came from the hub: each entity it touches takes the new value only if this write is newer than the
    /// last one that entity saw (timestamp, then device name). Applying in any order therefore ends in the same state everywhere.
    /// Must run inside a write transaction.
    static func applyRemote(_ r: RemoteOp, in db: Database) throws -> RemoteResult {
        let already = try Int64.fetchOne(db, sql: "SELECT local_id FROM ops WHERE origin_device = ? AND origin_id = ?", arguments: [r.originDevice, r.originID])
        if already != nil { return .ignored }
        let author = Author(rawValue: r.author) ?? .importer
        func record(kind: String) throws {
            try db.execute(sql: """
                INSERT INTO ops (device, author, kind, payload, inverse, created_at, ts, seq, origin_device, origin_id, local, pushed)
                VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, 0, 1)
                """, arguments: [r.originDevice, author.rawValue, kind, r.payload, r.createdAt, r.ts, r.seq, r.originDevice, r.originID])
        }
        // A change this build can't read (a newer app, a corrupted payload) is kept in the log, in order, but not applied,
        // so it can't block anyone else's sync.
        guard let op = try? JSONDecoder().decode(Op.self, from: Data(r.payload.utf8)) else {
            try record(kind: "unreadable")
            return .failed
        }
        var applied = false, failed = false
        for leaf in op.leaves {
            let keys = Array(leaf.entityKeys)
            let newer = try keys.allSatisfy { key in
                guard let c = try clock(of: key, db) else { return true }
                return (r.ts, r.originDevice) > (c.ts, c.device)
            }
            guard newer else { continue }
            do {
                try db.inSavepoint { _ = try Applier.apply(leaf, in: db); return .commit }
                applied = true
            } catch CoinboxError.notFound {
                // deleting something that is already gone
            } catch {
                failed = true
                continue
            }
            for key in keys { try setClock(key, ts: r.ts, device: r.originDevice, db) }
        }
        try observe(r.ts, db)
        try record(kind: op.kind)
        return failed ? .failed : (applied ? .applied : .ignored)
    }
}
