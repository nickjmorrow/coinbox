import Foundation

/// Where and as whom this install syncs. It holds a token, so it lives in its own file (mode 600) next to the database.
public struct SyncConfig: Codable, Sendable, Equatable {
    public var url: URL
    public var token: String
    /// Sent as the Host header (see `HTTPSyncTransport`); nil for a normal address.
    public var hostHeader: String?

    public init(url: URL, token: String, hostHeader: String? = nil) { self.url = url; self.token = token; self.hostHeader = hostHeader }

    public static func file(besideDatabaseAt path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).deletingLastPathComponent).appendingPathComponent("sync.json")
    }

    public static func load(besideDatabaseAt path: String) -> SyncConfig? {
        try? JSONDecoder().decode(SyncConfig.self, from: Data(contentsOf: file(besideDatabaseAt: path)))
    }

    public func save(besideDatabaseAt path: String) throws {
        let url = Self.file(besideDatabaseAt: path)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func transport() -> HTTPSyncTransport { HTTPSyncTransport(baseURL: url, token: token, hostHeader: hostHeader) }
}
