import ArgumentParser
import CoinboxCore
import Foundation

struct CoinboxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coinbox",
        abstract: "Budget data: plan, accounts, transactions. Prints JSON.",
        subcommands: [AccountGroup.self, CategoryGroupGroup.self, CategoryGroupCommand.self, PayeeGroup.self, TransactionGroup.self, TargetGroup.self, RuleGroup.self, SchemaCommand.self,
                      AssignCommand.self, MoveCommand.self, PlanCommand.self, AutoAssignCommand.self, CardTermsGroup.self, PayoffCommand.self, AmazonSplitCommand.self, AmazonLinkCommand.self, RunwayCommand.self, ReviewCommand.self, MoneyMovesCommand.self, ReconcileCommand.self, ImportYNAB.self, YNABCompare.self, SimpleFINClaim.self, SimpleFINLink.self, SimpleFINSync.self, SimpleFINAccounts.self, AICategorize.self,
                      MonthNoteGroup.self, SyncSetup.self, SyncCommand.self, SyncServe.self, SQLCommand.self, UndoCommand.self, ChangesCommand.self])
}

/// A month is "YYYY-MM"; anything else is refused before it reaches the database.
func validMonth(_ s: String) throws -> String {
    guard s.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil else {
        throw CoinboxError.invalid("month must look like 2026-01")
    }
    return s
}

// MARK: month notes

struct MonthNoteGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "month-note", abstract: "The free-text note on a month.",
                                                    subcommands: [Get.self, Set.self])

    struct Get: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var month: String
        func run() throws {
            let m = try validMonth(month)
            guard let note = try global.open().monthNote(m) else { throw CoinboxError.notFound("monthNote \(m)") }
            try Output.json(note)
        }
    }

    struct Set: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var month: String
        @Argument var text: String
        func run() throws {
            let note = MonthNote(month: try validMonth(month), text: text)
            try global.open().perform([.putMonthNote(note)], author: global.author)
            try Output.json(note)
        }
    }
}

// MARK: sql, undo, changes

struct SQLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "sql", abstract: "Run one read-only SELECT against the database.")
    @OptionGroup var global: GlobalOptions
    @Argument var statement: String
    @Option var limit = 500
    func run() throws { try Output.json(try global.open().query(sql: statement, limit: limit)) }
}

struct UndoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "undo", abstract: "Undo the latest change by --author (default claude).")
    @OptionGroup var global: GlobalOptions
    func run() throws { try Output.json(try global.open().undo(author: global.author)) }
}

struct ChangesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "changes", abstract: "The change log (milliseconds since epoch for --since).")
    @OptionGroup var global: GlobalOptions
    @Option var since: Int64 = 0
    @Option(name: .customLong("by"), help: "Only changes by this author: mac, iphone, claude, bank or import.") var by: Author?
    func run() throws { try Output.json(try global.open().changes(since: since, author: by)) }
}
