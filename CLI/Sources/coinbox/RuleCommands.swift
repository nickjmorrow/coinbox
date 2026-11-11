import ArgumentParser
import CoinboxCore
import Foundation

struct BatchOutput: Codable {
    var preview: Bool
    var changed: Int
    var brokenRules: [String]
    var changes: [PlannedChange]
}

/// Prints a planned batch and, unless previewing, performs it as one undoable change.
func finish(_ plan: PlannedBatch, preview: Bool, coinbox c: Coinbox, author: Author) throws {
    let broken = try c.rulesWithBrokenRegex().map(\.name)
    if !preview && !plan.ops.isEmpty { try c.perform(plan.ops, author: author) }
    try Output.json(BatchOutput(preview: preview, changed: plan.changes.filter { $0.skipped == nil }.count, brokenRules: broken, changes: plan.changes))
}

struct RuleGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rule", abstract: "Import rules: ordered, first match wins.",
                                                    subcommands: [List.self, Get.self, Put.self, PutMany.self, Delete.self, Apply.self])

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws { try Output.json(try global.open().rules()) }
    }
    struct Get: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        func run() throws {
            guard let r = try global.open().rule(id: id) else { throw CoinboxError.notFound("rule \(id)") }
            try Output.json(r)
        }
    }
    struct Put: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create or replace one rule from JSON: name, payee?, amount?, accountIDs?, memo?, actions, order?.")
        @OptionGroup var global: GlobalOptions
        @Option var json: String
        func run() throws {
            let r = try decodeJSON(Rule.self, json)
            try global.open().perform([.putRule(r)], author: global.author)
            try Output.json(r)
        }
    }
    struct PutMany: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "put-many", abstract: "Load a whole ruleset from a JSON array; a rule's order is its position in the array. --replace removes every other rule.")
        @OptionGroup var global: GlobalOptions
        @Option var json: String
        @Flag var replace = false
        func run() throws {
            let c = try global.open()
            var rules = try decodeJSON([Rule].self, json)
            for i in rules.indices { rules[i].order = i }
            var ops: [Op] = rules.map { .putRule($0) }
            if replace { let keep = Set(rules.map(\.id)); ops += try c.rules().filter { !keep.contains($0.id) }.map { .deleteRule(id: $0.id) } }
            try c.perform(ops, author: global.author)
            try Output.json(rules)
        }
    }
    struct Delete: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var id: String
        func run() throws {
            try global.open().perform([.deleteRule(id: id)], author: global.author)
            try Output.json(["deleted": id])
        }
    }
    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Run the rules over unapproved transactions (or --ids). --preview shows what would change and writes nothing.")
        @OptionGroup var global: GlobalOptions
        @Option(help: "Comma-separated transaction ids; default every unapproved transaction.") var ids: String?
        @Flag var preview = false
        func run() throws {
            let c = try global.open()
            let list = ids.map { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
            try finish(try c.planRuleApplication(ids: list), preview: preview, coinbox: c, author: global.author)
        }
    }
}

struct BulkApprove: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "approve", abstract: "Approve transactions (a transfer's other side is approved too).")
    @OptionGroup var global: GlobalOptions
    @Flag var preview = false
    @Argument var ids: [String]
    func run() throws { let c = try global.open(); try finish(try c.planApprove(ids: ids), preview: preview, coinbox: c, author: global.author) }
}

struct BulkCategorize: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "categorize", abstract: "Set one category on many transactions (splits and on-budget transfers are skipped and reported).")
    @OptionGroup var global: GlobalOptions
    @Option var category: String
    @Flag(help: "Also approve them.") var approve = false
    @Flag var preview = false
    @Argument var ids: [String]
    func run() throws { let c = try global.open(); try finish(try c.planCategorize(ids: ids, categoryID: category, approve: approve), preview: preview, coinbox: c, author: global.author) }
}

struct BulkDelete: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete-many", abstract: "Delete many transactions (a transfer's other side goes too).")
    @OptionGroup var global: GlobalOptions
    @Flag var preview = false
    @Argument var ids: [String]
    func run() throws { let c = try global.open(); try finish(try c.planDelete(ids: ids), preview: preview, coinbox: c, author: global.author) }
}

struct SchemaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "schema", abstract: "The database tables and columns, for writing sql queries. Amounts are milliunits (1/1000 dollar); dates are YYYY-MM-DD.")
    @OptionGroup var global: GlobalOptions
    struct Column: Codable { var name: String; var type: String }
    struct Table: Codable { var table: String; var columns: [Column] }
    func run() throws {
        let r = try global.open().query(sql: """
            SELECT m.name, p.name, p.type FROM sqlite_master m JOIN pragma_table_info(m.name) p
            WHERE m.type = 'table' AND m.name NOT IN ('ops', 'clocks', 'meta') ORDER BY m.name, p.cid
            """, limit: 2000)
        var tables: [Table] = []
        for row in r.rows {
            guard case let .text(t) = row[0], case let .text(c) = row[1], case let .text(ty) = row[2] else { continue }
            if tables.last?.table == t { tables[tables.count - 1].columns.append(Column(name: c, type: ty)) } else { tables.append(Table(table: t, columns: [Column(name: c, type: ty)])) }
        }
        try Output.json(tables)
    }
}
