import Foundation
import GRDB

/// Brings one device in step with the hub: sends what it has done, then applies what others have done.
public struct SyncClient: Sendable {
    let coinbox: Coinbox
    let transport: SyncTransport

    public init(coinbox: Coinbox, transport: SyncTransport) {
        self.coinbox = coinbox
        self.transport = transport
    }

    @discardableResult
    public func sync() async throws -> SyncReport {
        var report = SyncReport()
        let outgoing = try coinbox.outgoingOps()
        if !outgoing.isEmpty {
            try coinbox.markPushed(try await transport.push(device: coinbox.device, ops: outgoing))
            report.pushed = outgoing.count
        }
        while true {
            let since = Int64(try coinbox.meta("pulled_seq") ?? "0") ?? 0
            let batch = try await transport.pull(since: since)
            if batch.isEmpty { break }
            report.pulled += batch.count
            let counts = try coinbox.applyPulled(batch)
            report.applied += counts.applied
            report.failed += counts.failed
        }
        return report
    }
}
