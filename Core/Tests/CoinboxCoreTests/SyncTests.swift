import Foundation
import Testing
@testable import CoinboxCore

final class TestClock: @unchecked Sendable {
    var now: Int64
    init(_ start: Int64) { now = start }
    func tick(_ by: Int64 = 1000) { now += by }
}

/// Talks to a hub in the same process.
struct LocalTransport: SyncTransport {
    let hub: SyncHub
    let device: String
    func pull(since: Int64) async throws -> [RemoteOp] { try hub.pull(since: since) }
    func push(device: String, ops: [OutgoingOp]) async throws -> [SeqAssignment] { try hub.push(device: device, ops: ops) }
}

struct World {
    let hub: SyncHub
    let a: Coinbox, b: Coinbox
    let clockA: TestClock, clockB: TestClock

    init(clockA ca: Int64 = 1_000_000, clockB cb: Int64 = 1_000_000) throws {
        clockA = TestClock(ca); clockB = TestClock(cb)
        hub = SyncHub(coinbox: try Coinbox.inMemory(device: "hub", clock: { 1_000_000 }))
        a = try Coinbox.inMemory(device: "A", clock: { [clockA] in clockA.now })
        b = try Coinbox.inMemory(device: "B", clock: { [clockB] in clockB.now })
    }

    @discardableResult func sync(_ f: Coinbox) async throws -> SyncReport {
        try await SyncClient(coinbox: f, transport: LocalTransport(hub: hub, device: f.device)).sync()
    }

    func converged() throws -> Bool { try a.monthNotes() == b.monthNotes() }
}

/// Any string works as a month key at this layer, so tests use short ids.
func note(_ id: String, _ text: String) -> MonthNote { MonthNote(month: id, text: text) }

@Suite struct SyncTests {
    @Test func aChangeOnOneDeviceAppearsOnTheOther() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("e", "Squat")), .putMonthNote(note("r", "Legs"))], author: .mac)
        let report = try await w.sync(w.a)
        #expect(report.pushed == 1)
        try await w.sync(w.b)
        #expect(try w.b.monthNote("r")?.text == "Legs" && (try w.b.monthNote("e")?.text) == "Squat")
        #expect(try w.converged())
    }

    @Test func concurrentEditsConvergeOnTheLaterOne() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("r", "Start"))], author: .mac)
        try await w.sync(w.a); try await w.sync(w.b)
        w.clockA.tick(1000); try w.a.perform([.putMonthNote(note("r", "From A"))], author: .mac)
        w.clockB.tick(5000); try w.b.perform([.putMonthNote(note("r", "From B, later"))], author: .mac)
        try await w.sync(w.a); try await w.sync(w.b); try await w.sync(w.a)
        #expect(try w.a.monthNote("r")?.text == "From B, later")
        #expect(try w.converged())
    }

    @Test func syncOrderDoesNotChangeTheWinner() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("r", "Start"))], author: .mac)
        try await w.sync(w.a); try await w.sync(w.b)
        w.clockB.tick(5000); try w.b.perform([.putMonthNote(note("r", "B later"))], author: .mac)
        w.clockA.tick(1000); try w.a.perform([.putMonthNote(note("r", "A earlier"))], author: .mac)
        try await w.sync(w.b); try await w.sync(w.a); try await w.sync(w.b)     // B reaches the hub first this time
        #expect(try w.a.monthNote("r")?.text == "B later" && (try w.converged()))
    }

    @Test func aDeleteLaterThanAnEditWinsAndAnEditLaterThanADeleteWins() async throws {
        for editWins in [false, true] {
            let w = try World()
            try w.a.perform([.putMonthNote(note("r", "Start"))], author: .mac)
            try await w.sync(w.a); try await w.sync(w.b)
            if editWins {
                w.clockA.tick(1000); try w.a.perform([.deleteMonthNote(month: "r")], author: .mac)
                w.clockB.tick(9000); try w.b.perform([.putMonthNote(note("r", "Edited"))], author: .mac)
            } else {
                w.clockB.tick(1000); try w.b.perform([.putMonthNote(note("r", "Edited"))], author: .mac)
                w.clockA.tick(9000); try w.a.perform([.deleteMonthNote(month: "r")], author: .mac)
            }
            try await w.sync(w.a); try await w.sync(w.b); try await w.sync(w.a)
            #expect((try w.a.monthNote("r") != nil) == editWins)
            #expect(try w.converged())
        }
    }

    @Test func aStaleEditCannotResurrectADeletedThing() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("r", "Start"))], author: .mac)
        try await w.sync(w.a); try await w.sync(w.b)
        w.clockB.tick(1000); try w.b.perform([.putMonthNote(note("r", "Old edit"))], author: .mac)       // B offline
        w.clockA.tick(9000); try w.a.perform([.deleteMonthNote(month: "r")], author: .mac)
        try await w.sync(w.a)
        try await w.sync(w.b)                                                                              // B's older edit arrives after the delete
        try await w.sync(w.a)
        #expect(try w.a.monthNote("r") == nil && (try w.b.monthNote("r")) == nil)
    }

    @Test func aDeviceWhoseClockRunsBehindStillWinsAfterSeeingNewerWork() async throws {
        let w = try World(clockA: 9_000_000, clockB: 1_000_000)        // B's clock is far behind
        try w.a.perform([.putMonthNote(note("r", "From A"))], author: .mac)
        try await w.sync(w.a); try await w.sync(w.b)
        try w.b.perform([.putMonthNote(note("r", "B, after seeing A"))], author: .mac)   // wall clock says 1_000_000, but B has seen 9_000_000
        try await w.sync(w.b); try await w.sync(w.a)
        #expect(try w.a.monthNote("r")?.text == "B, after seeing A")
    }

    @Test func syncingAgainSendsNothingNew() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("r", "x"))], author: .mac)
        try await w.sync(w.a)
        let again = try await w.sync(w.a)
        #expect(again.pushed == 0)
        #expect(try w.hub.head() == 1)
    }

    @Test func retryingAPushIsIdempotent() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("r", "x"))], author: .mac)
        let op = try #require(try w.a.outgoingOps().first)
        let first = try w.hub.push(device: "A", ops: [op])
        let second = try w.hub.push(device: "A", ops: [op])
        #expect(first == second && first.count == 1)
        #expect(try w.hub.head() == 1)
    }

    @Test func anUndoOnOneDeviceUndoesItEverywhere() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("r", "Temp"))], author: .claude)
        try await w.sync(w.a); try await w.sync(w.b)
        #expect(try w.b.monthNote("r") != nil)
        w.clockA.tick(); try w.a.undo(author: .claude)
        try await w.sync(w.a); try await w.sync(w.b)
        #expect(try w.b.monthNote("r") == nil)
    }

    @Test func changesMadeDirectlyOnTheHubAreSequencedAndPulled() async throws {
        let w = try World()
        try w.hub.coinbox.perform([.putMonthNote(note("hubr", "From the hub"))], author: .claude)      // like the coinbox CLI on the server
        try await w.sync(w.a)
        #expect(try w.a.monthNote("hubr")?.text == "From the hub")
        #expect(try w.hub.head() == 1)
    }

    @Test func ownOpsComingBackAreNotAppliedTwice() async throws {
        let w = try World()
        try w.a.perform([.putMonthNote(note("r", "One"))], author: .mac)
        try await w.sync(w.a)
        let report = try await w.sync(w.a)
        #expect(report.applied == 0)
        #expect(try w.a.monthNotes().count == 1)
    }

}

@Suite struct DeviceIdentityTests {
    @Test func aDatabaseKeepsItsDeviceNameAcrossOpens() throws {
        let path = NSTemporaryDirectory() + "coinbox-dev-\(UUID().uuidString)/coinbox.sqlite"
        let first = try Coinbox.open(path: path, device: "phone")
        #expect(first.device == "phone")
        let second = try Coinbox.open(path: path, device: "something-else")
        #expect(second.device == "phone")          // the Mac app and the CLI share one file, so they are one device
    }
}

@Suite struct SyncHTTPTests {
    private func server() throws -> (SyncHTTP, Coinbox) {
        let hubCoinbox = try Coinbox.inMemory(device: "hub")
        return (SyncHTTP(hub: SyncHub(coinbox: hubCoinbox), tokens: ["secret": "iphone"]), hubCoinbox)
    }

    @Test func requestsNeedAKnownToken() throws {
        let (http, _) = try server()
        #expect(http.handle(method: "POST", path: "/sync/pull", query: [:], authorization: nil, body: Data()).status == 401)
        #expect(http.handle(method: "POST", path: "/sync/pull", query: [:], authorization: "Bearer nope", body: Data()).status == 401)
        #expect(http.handle(method: "POST", path: "/sync/pull", query: [:], authorization: "Bearer secret", body: Data()).status == 200)
        #expect(http.handle(method: "POST", path: "/sync/other", query: [:], authorization: "Bearer secret", body: Data()).status == 404)
    }

    @Test func pushThenPullRoundTripsThroughTheJSONAPI() throws {
        let (http, hubCoinbox) = try server()
        let device = try Coinbox.inMemory(device: "iphone")
        try device.perform([.putMonthNote(note("r", "Legs"))], author: .mac)
        let body = try JSONEncoder().encode(SyncHTTP.PushBody(device: "iphone", ops: try device.outgoingOps()))
        let pushed = http.handle(method: "POST", path: "/sync/push", query: [:], authorization: "Bearer secret", body: body)
        #expect(pushed.status == 200)
        #expect(try JSONDecoder().decode([SeqAssignment].self, from: pushed.body).count == 1)
        #expect(try hubCoinbox.monthNote("r")?.text == "Legs")
        let pulled = http.handle(method: "POST", path: "/sync/pull", query: ["since": "0"], authorization: "Bearer secret", body: Data())
        #expect(try JSONDecoder().decode([RemoteOp].self, from: pulled.body).count == 1)
    }

    @Test func malformedBodiesAreRejected() throws {
        let (http, _) = try server()
        #expect(http.handle(method: "POST", path: "/sync/push", query: [:], authorization: "Bearer secret", body: Data("nope".utf8)).status == 400)
        #expect(http.handle(method: "POST", path: "/sync/pull", query: ["since": "x"], authorization: "Bearer secret", body: Data()).status == 400)
    }
}


@Suite struct SyncRobustnessTests {
    private func world() throws -> (hub: SyncHub, a: Coinbox, b: Coinbox, clockA: TestClock, clockB: TestClock) {
        let ca = TestClock(1_000_000), cb = TestClock(1_000_000)
        return (SyncHub(coinbox: try Coinbox.inMemory(device: "hub", clock: { 1_000_000 })),
                try Coinbox.inMemory(device: "A", clock: { ca.now }), try Coinbox.inMemory(device: "B", clock: { cb.now }), ca, cb)
    }

    private func sync(_ f: Coinbox, _ hub: SyncHub) async throws -> SyncReport {
        try await SyncClient(coinbox: f, transport: LocalTransport(hub: hub, device: f.device)).sync()
    }

    @Test func anUnreadableOpDoesNotWedgeAnyone() async throws {
        let w = try world()
        try w.b.perform([.putMonthNote(note("good", "Good"))], author: .mac)
        let good = try #require(try w.b.outgoingOps().first)
        let bad = OutgoingOp(localID: 1, author: "mac", payload: "not json at all", createdAt: 1, ts: 5)
        let seqs = try w.hub.push(device: "X", ops: [bad, OutgoingOp(localID: 2, author: good.author, payload: good.payload, createdAt: good.createdAt, ts: good.ts)])
        #expect(seqs.count == 2)
        let first = try await sync(w.a, w.hub)
        let received = try w.a.monthNote("good")
        #expect(first.failed == 1 && received != nil)
        let again = try await sync(w.a, w.hub)
        #expect(again.pulled == 0 && again.failed == 0)
    }

    @Test func anUnknownAuthorIsTolerated() async throws {
        let w = try world()
        try w.b.perform([.putMonthNote(note("r", "R"))], author: .mac)
        let op = try #require(try w.b.outgoingOps().first)
        _ = try w.hub.push(device: "B", ops: [OutgoingOp(localID: op.localID, author: "hacker", payload: op.payload, createdAt: op.createdAt, ts: op.ts)])
        let changes = try w.hub.coinbox.changes(since: 0)
        #expect(changes.count == 1 && changes[0].author == .importer)
        _ = try await sync(w.a, w.hub)
        #expect(try w.a.changes(since: 0).count == 1)
    }

    @Test func undoIsBlockedByALaterEditFromAnotherDeviceOfTheSameAuthor() async throws {
        let w = try world()
        try w.a.perform([.putMonthNote(note("r", "v1"))], author: .mac)
        _ = try await sync(w.a, w.hub); _ = try await sync(w.b, w.hub)
        w.clockA.tick(); try w.a.perform([.putMonthNote(note("r", "v2"))], author: .mac)
        _ = try await sync(w.a, w.hub); _ = try await sync(w.b, w.hub)
        w.clockB.tick(5000); try w.b.perform([.putMonthNote(note("r", "v3"))], author: .mac)
        _ = try await sync(w.b, w.hub); _ = try await sync(w.a, w.hub)
        let result = try w.a.undo(author: .mac)
        #expect(result.undone == 0 && result.skipped.count == 1)
        #expect(try w.a.monthNote("r")?.text == "v3")
    }

    @Test func twoConnectionsToOneFileDoNotLockEachOtherOut() throws {
        let path = NSTemporaryDirectory() + "coinbox-busy-\(UUID().uuidString)/coinbox.sqlite"
        let one = try Coinbox.open(path: path, device: "one"), two = try Coinbox.open(path: path, device: "two")
        let lock = NSLock()
        nonisolated(unsafe) var failures = 0
        DispatchQueue.concurrentPerform(iterations: 2) { i in
            let f = i == 0 ? one : two
            for n in 0..<80 {
                do { try f.perform([.putMonthNote(note("r\(i)-\(n)", "x"))], author: .mac) } catch { lock.lock(); failures += 1; lock.unlock() }
            }
        }
        #expect(failures == 0)
        #expect(try one.monthNotes().count == 160)
    }

    @Test func firstOpensRacingEachOtherAllSucceed() throws {
        let path = NSTemporaryDirectory() + "coinbox-first-\(UUID().uuidString)/coinbox.sqlite"
        let lock = NSLock()
        nonisolated(unsafe) var failures = 0
        DispatchQueue.concurrentPerform(iterations: 4) { i in
            do { _ = try Coinbox.open(path: path, device: "d\(i)") } catch { lock.lock(); failures += 1; lock.unlock() }
        }
        #expect(failures == 0)
    }
}

private final class CapturingProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var last: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.last = request
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct HTTPTransportTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func requestsCarryTheTokenAndAnOptionalHostHeader() async throws {
        let transport = HTTPSyncTransport(baseURL: URL(string: "http://100.64.0.1:8452")!, token: "tok", hostHeader: "hub.example.ts.net:8452", session: session())
        _ = try await transport.pull(since: 7)
        let request = try #require(CapturingProtocol.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Host") == "hub.example.ts.net:8452")
        #expect(request.url?.path == "/sync/pull" && request.url?.query == "since=7")
        let plain = HTTPSyncTransport(baseURL: URL(string: "http://100.64.0.1:8452")!, token: "tok", session: session())
        _ = try await plain.pull(since: 0)
        #expect(CapturingProtocol.last?.value(forHTTPHeaderField: "Host") == nil)
    }

    @Test func configRoundTripsTheHostHeader() throws {
        let path = NSTemporaryDirectory() + "coinbox-cfg-\(UUID().uuidString)/coinbox.sqlite"
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try SyncConfig(url: URL(string: "http://100.64.0.1:8452")!, token: "t", hostHeader: "hub.example.ts.net:8452").save(besideDatabaseAt: path)
        #expect(SyncConfig.load(besideDatabaseAt: path)?.hostHeader == "hub.example.ts.net:8452")
        try SyncConfig(url: URL(string: "http://x")!, token: "t").save(besideDatabaseAt: path)
        #expect(SyncConfig.load(besideDatabaseAt: path)?.hostHeader == nil)
    }
}
