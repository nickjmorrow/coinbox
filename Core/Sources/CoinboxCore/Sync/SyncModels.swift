import Foundation

/// A change as the hub numbered it.
public struct RemoteOp: Codable, Sendable, Equatable {
    public var seq: Int64
    public var originDevice: String
    public var originID: Int64
    public var author: String
    public var payload: String
    public var createdAt: Int64
    public var ts: Int64
    public init(seq: Int64, originDevice: String, originID: Int64, author: String, payload: String, createdAt: Int64, ts: Int64) {
        self.seq = seq; self.originDevice = originDevice; self.originID = originID; self.author = author
        self.payload = payload; self.createdAt = createdAt; self.ts = ts
    }
}

/// A change this device made that the hub hasn't numbered yet.
public struct OutgoingOp: Codable, Sendable, Equatable {
    public var localID: Int64
    public var author: String
    public var payload: String
    public var createdAt: Int64
    public var ts: Int64
    public init(localID: Int64, author: String, payload: String, createdAt: Int64, ts: Int64) {
        self.localID = localID; self.author = author; self.payload = payload; self.createdAt = createdAt; self.ts = ts
    }
}

public struct SeqAssignment: Codable, Sendable, Equatable {
    public var localID: Int64
    public var seq: Int64
}

/// How a device talks to the hub: over HTTP in the apps, in-process in tests.
public protocol SyncTransport: Sendable {
    func pull(since: Int64) async throws -> [RemoteOp]
    func push(device: String, ops: [OutgoingOp]) async throws -> [SeqAssignment]
}

public struct SyncReport: Codable, Sendable, Equatable {
    public var pushed = 0
    public var pulled = 0
    public var applied = 0
    public var failed = 0
    public init() {}
}
