import Foundation
import GRDB

/// A Coinbox database: exercises, routines, workouts and the op log.
public final class Coinbox: Sendable {
    public let db: DatabaseQueue
    public let device: String
    /// Wall-clock milliseconds; replaceable so tests can give each device its own (possibly skewed) clock.
    let clock: @Sendable () -> Int64

    init(db: DatabaseQueue, device: String, clock: @escaping @Sendable () -> Int64 = Coinbox.nowMillis) throws {
        try Schema.migrator().migrate(db)
        // A database is one device for sync purposes, however many processes open it (the Mac app and the CLI share a file).
        if let stored = try db.read({ try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = 'device'") }) {
            self.device = stored
        } else {
            try db.write { try $0.execute(sql: "INSERT INTO meta (key, value) VALUES ('device', ?)", arguments: [device]) }
            self.device = device
        }
        self.db = db
        self.clock = clock
    }

    public static func open(path: String, device: String, clock: @escaping @Sendable () -> Int64 = Coinbox.nowMillis) throws -> Coinbox {
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty { try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.busyMode = .timeout(10)      // another process (the app, the CLI, the hub) may be mid-write
        config.prepareDatabase { db in
            if !db.configuration.readonly, try String.fetchOne(db, sql: "PRAGMA journal_mode") != "wal" {
                try db.execute(sql: "PRAGMA journal_mode = WAL")
            }
        }
        let queue = try DatabaseQueue(path: path, configuration: config)
        return try Coinbox(db: queue, device: device, clock: clock)
    }

    public static func inMemory(device: String = "test", clock: @escaping @Sendable () -> Int64 = Coinbox.nowMillis) throws -> Coinbox {
        var config = Configuration()
        config.foreignKeysEnabled = true
        return try Coinbox(db: try DatabaseQueue(configuration: config), device: device, clock: clock)
    }

    public static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

extension Coinbox {
    /// Changes whenever a different connection (another process, such as the `coinbox` CLI) commits to the file; own writes don't change it.
    public func dataVersion() throws -> Int {
        try db.read { try Int.fetchOne($0, sql: "PRAGMA data_version") ?? 0 }
    }
}
