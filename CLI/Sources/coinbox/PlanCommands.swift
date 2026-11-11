import ArgumentParser
import CoinboxCore
import Foundation

struct AssignCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "assign", abstract: "Set what a category is assigned in a month, in dollars (replaces the old amount).")
    @OptionGroup var global: GlobalOptions
    @Argument var categoryID: String
    @Argument var month: String
    @Argument var dollars: String
    func run() throws {
        let a = Assignment(categoryID: categoryID, month: try validMonth(month), amount: try parseDollars(dollars))
        try global.open().perform([.putAssignment(a)], author: global.author)
        try Output.json(a)
    }
}

struct MoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "move", abstract: "Move money between two categories in a month: lowers the first's assignment and raises the second's, as one change.")
    @OptionGroup var global: GlobalOptions
    @Argument var fromCategoryID: String
    @Argument var toCategoryID: String
    @Argument var month: String
    @Argument var dollars: String
    func run() throws {
        let c = try global.open()
        let m = try validMonth(month), amount = try parseDollars(dollars)
        guard amount > 0 else { throw CoinboxError.invalid("the amount to move must be positive") }
        func current(_ id: String) throws -> Milliunits { try c.assignment(categoryID: id, month: m)?.amount ?? 0 }
        let from = Assignment(categoryID: fromCategoryID, month: m, amount: try current(fromCategoryID) - amount)
        let to = Assignment(categoryID: toCategoryID, month: m, amount: try current(toCategoryID) + amount)
        try c.perform([.putAssignment(from), .putAssignment(to)], author: global.author)
        try Output.json([from, to])
    }
}

struct PlanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "plan", abstract: "The plan for a month: Ready to Assign and every category's assigned, activity and available.")
    @OptionGroup var global: GlobalOptions
    @Argument var month: String

    struct Row: Codable { var id: String; var name: String; var assigned: Milliunits; var activity: Milliunits; var available: Milliunits
                          var underfunded: Milliunits; var cashOverspent: Milliunits; var creditOverspent: Milliunits; var hidden: Bool }
    struct Group: Codable { var name: String; var categories: [Row] }
    struct Output: Codable { var month: String; var readyToAssign: Milliunits; var readyToAssignDisplay: String; var cashOverspending: Milliunits; var groups: [Group] }

    func run() throws {
        let c = try global.open()
        let key = MonthKey(try validMonth(month))!
        let s = try c.budget(for: key)
        let cats = try c.categories()
        let groups = try c.categoryGroups().map { g -> Group in
            let rows = cats.filter { $0.groupID == g.id && $0.kind != .readyToAssign }.compactMap { cat -> Row? in
                guard let m = s.categories[cat.id] else { return nil }
                return Row(id: cat.id, name: cat.name, assigned: m.assigned, activity: m.activity, available: m.available, underfunded: m.underfunded,
                           cashOverspent: m.cashOverspent, creditOverspent: m.creditOverspent, hidden: cat.hidden || g.hidden)
            }
            return Group(name: g.name, categories: rows)
        }.filter { !$0.categories.isEmpty }
        try coinbox.Output.json(Output(month: key.string, readyToAssign: s.readyToAssign, readyToAssignDisplay: Money.format(s.readyToAssign),
                                       cashOverspending: s.cashOverspending, groups: groups))
    }
}

struct AutoAssignCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "auto-assign", abstract: "Assign every underfunded category what it needs, in plan order, until Ready to Assign runs out. --preview only reports.")
    @OptionGroup var global: GlobalOptions
    @Flag var preview = false
    @Argument var month: String
    struct Output: Codable { var preview: Bool; var assigned: Milliunits; var readyToAssignLeft: Milliunits; var assignments: [Assignment] }
    func run() throws {
        let c = try global.open()
        let r = try c.autoAssignOps(month: MonthKey(try validMonth(month))!)
        if !preview && !r.ops.isEmpty { try c.perform(r.ops, author: global.author) }
        let list = r.ops.compactMap { op -> Assignment? in if case let .putAssignment(a) = op { return a } else { return nil } }
        try coinbox.Output.json(Output(preview: preview, assigned: r.assigned, readyToAssignLeft: r.readyToAssignLeft, assignments: list))
    }
}

struct ReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "review", abstract: "How a month's money went, by group and category, next to the following month's plan.")
    @OptionGroup var global: GlobalOptions
    @Argument var month: String
    func run() throws { try Output.json(try global.open().monthReview(MonthKey(try validMonth(month))!)) }
}

struct RunwayCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "runway", abstract: "Cash in on-budget cash accounts divided by Cost to Be Me (the monthly need of every target), in months.")
    @OptionGroup var global: GlobalOptions
    @Option(help: "Month to price targets in (default: this month).") var month: String?
    func run() throws {
        let key = try month.map { MonthKey(try validMonth($0))! } ?? MonthKey.containing(date: ISO8601DateFormatter().string(from: Date()).prefix(10).description)!
        try Output.json(try global.open().runway(asOf: key))
    }
}

struct MoneyMovesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "money-moves", abstract: "Who changed what was assigned in a month, newest first.")
    @OptionGroup var global: GlobalOptions
    @Argument var month: String
    func run() throws { try Output.json(try global.open().moneyMoves(month: try validMonth(month))) }
}

struct ReconcileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "reconcile", abstract: "Lock an account's cleared transactions as reconciled against the bank's balance (dollars). A difference needs --adjust.")
    @OptionGroup var global: GlobalOptions
    @Argument var accountID: String
    @Option(help: "The statement date, 2026-01-31.") var date: String
    @Option(help: "The bank's balance, in dollars.") var balance: String
    @Flag(help: "Add a Reconciliation Balance Adjustment for any difference.") var adjust = false
    func run() throws {
        let c = try global.open()
        try c.perform(try c.reconcileOps(accountID: accountID, date: date, bankBalance: try parseDollars(balance), adjust: adjust, author: global.author), author: global.author)
        try Output.json(try c.account(id: accountID))
    }
}
