import ArgumentParser
import CoinboxCore
import Foundation

enum SimpleFINAccess {
    static let defaultFile = "~/.config/coinbox/simplefin_access_url"

    /// The fetcher for the access URL kept in `file`. Errors name the file, never the secret.
    static func fetcher(file: String) throws -> SimpleFINFetcher {
        let path = (file as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw CoinboxError.invalid("no SimpleFIN access URL at \(path); run `coinbox simplefin-claim --token <setup token>` or put the URL there (mode 600)")
        }
        return try HTTPSimpleFINFetcher(accessURL: text)
    }
}

/// One bank import at a time, no more often than once a minute (SimpleFIN allows about 24 requests a day).
actor SimpleFINJob {
    let coinbox: Coinbox
    let fetcher: SimpleFINFetcher
    let timeZone: TimeZone
    private var lastRun: Date?

    init(coinbox: Coinbox, fetcher: SimpleFINFetcher, timeZone: TimeZone) { self.coinbox = coinbox; self.fetcher = fetcher; self.timeZone = timeZone }

    func refresh(force: Bool = false) async -> SyncHTTP.Response {
        if !force, let lastRun, Date().timeIntervalSince(lastRun) < 60 {
            return SyncHTTP.Response(status: 429, contentType: "text/plain", body: Data("refreshed under a minute ago".utf8))
        }
        lastRun = Date()
        do {
            let report = try await coinbox.runSimpleFINSync(fetcher: fetcher, timeZone: timeZone)
            return SyncHTTP.Response(status: 200, body: (try? JSONEncoder().encode(report)) ?? Data("{}".utf8))
        } catch {
            let message = SimpleFIN.redact((error as? CoinboxError)?.message ?? "\(error)")
            return SyncHTTP.Response(status: 502, contentType: "text/plain", body: Data(message.utf8))
        }
    }
}

struct SimpleFINClaim: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "simplefin-claim", abstract: "Trade a SimpleFIN setup token for the access URL and save it privately (mode 600). The URL is never printed.")
    @Option var token: String
    @Option(name: .customLong("access-file")) var accessFile = SimpleFINAccess.defaultFile
    func run() async throws {
        let access = try await SimpleFIN.claim(setupToken: token)
        let path = (accessFile as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data((access + "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        try Output.json(["saved": path])
    }
}

struct SimpleFINLink: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "simplefin-link", abstract: "Link a SimpleFIN account id to a Coinbox account, so its activity imports there.")
    @OptionGroup var global: GlobalOptions
    @Argument var simplefinID: String
    @Argument var accountID: String
    func run() throws {
        let c = try global.open()
        guard var a = try c.account(id: accountID) else { throw CoinboxError.notFound("account \(accountID)") }
        a.simplefinID = simplefinID
        try c.perform([.putAccount(a)], author: global.author)
        try Output.json(a)
    }
}

struct SimpleFINSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "simplefin-sync", abstract: "Import bank activity from SimpleFIN as unapproved rows, link card payments, then run the rules. --preview only reports.")
    @OptionGroup var global: GlobalOptions
    @Option(name: .customLong("from-file"), help: "Read a saved /accounts response instead of calling SimpleFIN.") var fromFile: String?
    @Option(name: .customLong("access-file")) var accessFile = SimpleFINAccess.defaultFile
    @Option(help: "How many days back to ask for.") var days = 30
    @Option(help: "Time zone for bank dates.") var timezone = TimeZone.current.identifier
    @Flag var preview = false

    func run() async throws {
        let c = try global.open()
        let zone = TimeZone(identifier: timezone) ?? .current
        let fetcher: SimpleFINFetcher = try fromFile.map { FileSimpleFINFetcher(url: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) } ?? SimpleFINAccess.fetcher(file: accessFile)
        if preview {
            let data = try await fetcher.fetch(since: Date().addingTimeInterval(-Double(days) * 86_400))
            guard let response = try? JSONDecoder().decode(SFResponse.self, from: data) else { throw CoinboxError.invalid("SimpleFIN answered with something unreadable") }
            try Output.json(try c.planSimpleFINImport(response, timeZone: zone).report)
        } else {
            try Output.json(try await c.runSimpleFINSync(fetcher: fetcher, days: days, timeZone: zone))
        }
    }
}

struct SimpleFINAccounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "simplefin-accounts", abstract: "List the accounts SimpleFIN can see (id, bank, name, balance) and which Coinbox account each is linked to.")
    @OptionGroup var global: GlobalOptions
    @Option(name: .customLong("from-file")) var fromFile: String?
    @Option(name: .customLong("access-file")) var accessFile = SimpleFINAccess.defaultFile

    struct Row: Codable { var simplefinID: String; var bank: String?; var name: String; var balance: String; var linkedTo: String? }

    func run() async throws {
        let c = try global.open()
        let fetcher: SimpleFINFetcher = try fromFile.map { FileSimpleFINFetcher(url: URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) } ?? SimpleFINAccess.fetcher(file: accessFile)
        let data = try await fetcher.fetch(since: Date())
        guard let response = try? JSONDecoder().decode(SFResponse.self, from: data) else { throw CoinboxError.invalid("SimpleFIN answered with something unreadable") }
        let linked = Dictionary(try c.accounts().compactMap { a in a.simplefinID.map { ($0, a.name) } }, uniquingKeysWith: { a, _ in a })
        try Output.json(response.accounts.map { Row(simplefinID: $0.id, bank: $0.orgName, name: $0.name, balance: $0.balance, linkedTo: linked[$0.id]) })
    }
}
