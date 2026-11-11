import Foundation
import GRDB

/// The hub numbers every change in one global order and applies each device's changes with the same last-writer-wins rule the
/// devices use. It is just a Coinbox database plus this wrapper, so the `coinbox` CLI can work on the hub's database directly.
public final class SyncHub: Sendable {
    public let coinbox: Coinbox

    public init(coinbox: Coinbox) { self.coinbox = coinbox }

    public func head() throws -> Int64 {
        try coinbox.db.read { try Int64.fetchOne($0, sql: "SELECT COALESCE(MAX(seq), 0) FROM ops") ?? 0 }
    }

    /// Changes made directly on the hub's database (the `coinbox` CLI on the server) already took effect; give them their place in the order.
    private static func sequenceLocal(_ db: Database) throws {
        var head = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(seq), 0) FROM ops") ?? 0
        for id in try Int64.fetchAll(db, sql: "SELECT local_id FROM ops WHERE local = 1 AND seq IS NULL ORDER BY local_id") {
            head += 1
            try db.execute(sql: "UPDATE ops SET seq = ?, pushed = 1 WHERE local_id = ?", arguments: [head, id])
        }
    }

    public func pull(since: Int64, limit: Int = 2000) throws -> [RemoteOp] {
        try coinbox.db.write { try Self.sequenceLocal($0) }
        return try coinbox.db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT seq, origin_device, origin_id, author, payload, created_at, ts FROM ops WHERE seq > ? ORDER BY seq LIMIT ?
                """, arguments: [since, limit]).map {
                RemoteOp(seq: $0["seq"], originDevice: $0["origin_device"], originID: $0["origin_id"], author: $0["author"],
                         payload: $0["payload"], createdAt: $0["created_at"], ts: $0["ts"])
            }
        }
    }

    /// Takes a device's changes in order. Anything already taken (a retry) just gets its old number back.
    public func push(device: String, ops: [OutgoingOp]) throws -> [SeqAssignment] {
        try coinbox.db.write { db in
            try Self.sequenceLocal(db)
            var head = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(seq), 0) FROM ops") ?? 0
            var assigned: [SeqAssignment] = []
            for o in ops {
                if let seq = try Int64.fetchOne(db, sql: "SELECT seq FROM ops WHERE origin_device = ? AND origin_id = ? AND seq IS NOT NULL", arguments: [device, o.localID]) {
                    assigned.append(SeqAssignment(localID: o.localID, seq: seq))
                    continue
                }
                head += 1
                _ = try Coinbox.applyRemote(RemoteOp(seq: head, originDevice: device, originID: o.localID, author: o.author, payload: o.payload,
                                                   createdAt: o.createdAt, ts: o.ts), in: db)
                assigned.append(SeqAssignment(localID: o.localID, seq: head))
            }
            return assigned
        }
    }
}
