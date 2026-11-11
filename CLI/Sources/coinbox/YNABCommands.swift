import ArgumentParser
import CoinboxCore
import Foundation

struct YNABSourceOptions: ParsableArguments {
    @Option(help: "The YNAB plan (budget) id. Not needed with --from-dir.") var plan: String?
    @Option(name: .customLong("from-dir"), help: "Read saved API responses from this folder instead of calling YNAB.") var fromDir: String?
    @Option(help: "Import from this date on.") var since = "2026-01-01"

    func source() throws -> YNABSource {
        if let fromDir { return YNABSource(DirectoryYNABFetcher(directory: URL(fileURLWithPath: fromDir))) }
        guard let token = ProcessInfo.processInfo.environment["YNAB_TOKEN"], !token.isEmpty else {
            throw CoinboxError.invalid("set YNAB_TOKEN to a YNAB personal access token, or pass --from-dir")
        }
        guard let plan else { throw CoinboxError.invalid("pass --plan <YNAB plan id>") }
        return YNABSource(HTTPYNABFetcher(token: token, planID: plan))
    }
}

struct ImportYNAB: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "import-ynab", abstract: "Rebuild the plan from YNAB (read only). Without --apply it only reports.")
    @OptionGroup var global: GlobalOptions
    @OptionGroup var source: YNABSourceOptions
    @Flag(help: "Write the import. Without it nothing changes.") var apply = false
    @Flag(name: .customLong("plug-opening-rta"), help: "Add one inflow so Ready to Assign matches YNAB's first month.") var plug = false
    @Option(name: .customLong("interest-category"), help: "A YNAB category to treat as card interest (never overspent, never assigned). Left out, every category is ordinary.") var interest: String?

    struct Result: Codable { var applied: Bool; var opsToApply: Int; var report: YNABReport }

    func run() async throws {
        let options = YNABOptions(interestCategoryName: interest, plugOpeningRTA: plug)
        let snapshot = try await source.source().snapshot(since: source.since)
        var desired = YNABMapper.map(snapshot, since: source.since, options: options)
        try YNABImporter.finalize(&desired, snapshot: snapshot, since: source.since, options: options)
        let c = try global.open()
        let ops = try c.planYNABImport(desired)
        if apply { try c.applyYNABImport(ops) }
        try Output.json(Result(applied: apply, opsToApply: ops.count, report: desired.report))
    }
}

struct YNABCompare: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ynab-compare", abstract: "List every number that differs from YNAB's (months, categories, accounts).")
    @OptionGroup var global: GlobalOptions
    @OptionGroup var source: YNABSourceOptions

    func run() async throws {
        let snapshot = try await source.source().snapshot(since: source.since)
        try Output.json(try global.open().compareToYNAB(snapshot))
    }
}
