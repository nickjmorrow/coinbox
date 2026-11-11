import Foundation

/// The hub's HTTP API as a pure function, so it can be tested without sockets; `coinbox sync-serve` only does the networking.
///
///     POST /sync/pull?since=N    → [RemoteOp]
///     POST /sync/push            {device, ops:[OutgoingOp]} → [SeqAssignment]
public struct SyncHTTP: Sendable {
    public let hub: SyncHub
    /// Bearer token → a label for whoever holds it (only used to decide who may connect; devices name themselves).
    public let tokens: [String: String]
    public static let maxBody = 64 * 1024 * 1024

    public init(hub: SyncHub, tokens: [String: String]) { self.hub = hub; self.tokens = tokens }

    public struct Response: Sendable {
        public var status: Int
        public var contentType = "application/json"
        public var body: Data
        public init(status: Int, contentType: String = "application/json", body: Data) { self.status = status; self.contentType = contentType; self.body = body }
    }

    struct PushBody: Codable { var device: String; var ops: [OutgoingOp] }

    public func isAuthorized(_ authorization: String?) -> Bool {
        guard let a = authorization, a.hasPrefix("Bearer ") else { return false }
        return tokens[String(a.dropFirst(7))] != nil
    }

    public func handle(method: String, path: String, query: [String: String], authorization: String?, body: Data) -> Response {
        guard isAuthorized(authorization) else { return text(401, "unauthorized") }
        do {
            switch (method, path) {
            case ("POST", "/sync/pull"):
                guard let since = Int64(query["since"] ?? "0") else { return text(400, "bad since") }
                return json(try hub.pull(since: since))
            case ("POST", "/sync/push"):
                guard let b = try? JSONDecoder().decode(PushBody.self, from: body) else { return text(400, "bad body") }
                return json(try hub.push(device: b.device, ops: b.ops))
            default: return text(404, "not found")
            }
        } catch { return text(500, "server error") }
    }

    private func text(_ status: Int, _ s: String) -> Response { Response(status: status, contentType: "text/plain", body: Data(s.utf8)) }
    private func json<T: Encodable>(_ v: T) -> Response { Response(status: 200, body: (try? JSONEncoder().encode(v)) ?? Data("null".utf8)) }
}

public enum SyncHTTPError: Error, Equatable { case status(Int, String) }

/// Talks to a `coinbox sync-serve` server with this device's bearer token.
public final class HTTPSyncTransport: SyncTransport, @unchecked Sendable {
    let base: URL
    let token: String
    let session: URLSession
    let hostHeader: String?

    /// `hostHeader` lets a device reach the hub by its tailnet IP while Tailscale's front door still routes by name.
    public init(baseURL: URL, token: String, hostHeader: String? = nil, session: URLSession = .shared) {
        base = baseURL; self.token = token; self.hostHeader = hostHeader; self.session = session
    }

    private func post(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let hostHeader { req.setValue(hostHeader, forHTTPHeaderField: "Host") }
        req.httpBody = body
        req.timeoutInterval = 60
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SyncHTTPError.status(status, String(decoding: data, as: UTF8.self)) }
        return data
    }

    public func pull(since: Int64) async throws -> [RemoteOp] {
        try JSONDecoder().decode([RemoteOp].self, from: try await post("sync/pull", query: [URLQueryItem(name: "since", value: String(since))]))
    }

    public func push(device: String, ops: [OutgoingOp]) async throws -> [SeqAssignment] {
        try JSONDecoder().decode([SeqAssignment].self, from: try await post("sync/push", body: try JSONEncoder().encode(SyncHTTP.PushBody(device: device, ops: ops))))
    }
}
