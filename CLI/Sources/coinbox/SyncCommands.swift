import ArgumentParser
import CoinboxCore
import Foundation

struct SyncSetup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sync-setup", abstract: "Save the hub address and token for this database (kept in sync.json beside it, readable only by you).")
    @OptionGroup var global: GlobalOptions
    @Option(help: "Hub URL, like https://hub.example.ts.net/coinbox.") var url: String
    @Option(help: "This install's token from the hub's tokens file.") var token: String
    @Option(name: .customLong("host-header"), help: "Send this Host header (to reach the hub by its tailnet IP while Tailscale routes by name).") var hostHeader: String?
    func run() throws {
        guard let parsed = URL(string: url), parsed.scheme != nil, parsed.host != nil else { throw CoinboxError.invalid("--url must look like https://host/path") }
        let coinbox = try global.open()
        try SyncConfig(url: parsed, token: token, hostHeader: hostHeader).save(besideDatabaseAt: global.databasePath)
        try Output.json(["configured": "true", "device": coinbox.device, "file": SyncConfig.file(besideDatabaseAt: global.databasePath).path])
    }
}

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sync", abstract: "Send this database's changes to the hub and apply everyone else's.")
    @OptionGroup var global: GlobalOptions
    func run() async throws {
        guard let config = SyncConfig.load(besideDatabaseAt: global.databasePath) else {
            throw CoinboxError.invalid("sync isn't set up here: run coinbox sync-setup --url <hub url> --token <token>")
        }
        let coinbox = try global.open()
        try Output.json(try await SyncClient(coinbox: coinbox, transport: config.transport()).sync())
    }
}

struct SyncServe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sync-serve", abstract: "Run the sync hub on 127.0.0.1 over this database (put `tailscale serve` in front of it).")
    @OptionGroup var global: GlobalOptions
    @Option(help: "JSON file mapping tokens to a label, e.g. {\"<token>\": \"iphone\"}.") var tokens: String
    @Option(help: "Port on 127.0.0.1.") var port: UInt16 = 8790
    @Option(name: .customLong("simplefin-access-file"), help: "File holding the SimpleFIN access URL. With it the hub imports bank activity on a timer and on POST /simplefin/refresh.") var simplefinFile: String?
    @Option(name: .customLong("simplefin-hours"), help: "Hours between automatic bank imports.") var simplefinHours = 6
    @Option(help: "Time zone for bank dates.") var timezone = TimeZone.current.identifier

    func run() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: (tokens as NSString).expandingTildeInPath))
        guard let map = try JSONSerialization.jsonObject(with: data) as? [String: String], !map.isEmpty else {
            throw CoinboxError.invalid("tokens file must be a non-empty JSON object of token → label")
        }
        let job: SimpleFINJob? = try simplefinFile.map {
            SimpleFINJob(coinbox: try global.open(), fetcher: try SimpleFINAccess.fetcher(file: $0), timeZone: TimeZone(identifier: timezone) ?? .current)
        }
        var refresh: SyncServer.Refresh?
        if let job { refresh = { await job.refresh() } }
        let server = try SyncServer(http: SyncHTTP(hub: SyncHub(coinbox: try global.open()), tokens: map), port: port, refresh: refresh)
        let actual = try server.start()
        print("coinbox sync hub listening on 127.0.0.1:\(actual), \(map.count) token(s)" + (job == nil ? "" : ", bank import every \(simplefinHours) h"))
        fflush(stdout)
        if let job {
            Task {
                while true {
                    let response = await job.refresh(force: true)
                    print("simplefin import: HTTP \(response.status) \(String(decoding: response.body.prefix(300), as: UTF8.self))")
                    fflush(stdout)
                    try? await Task.sleep(nanoseconds: UInt64(max(1, simplefinHours)) * 3_600_000_000_000)
                }
            }
        }
        while true { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
    }
}
