import ArgumentParser
import CoinboxCore
import Foundation

func decodeJSON<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    do { return try JSONDecoder().decode(T.self, from: Data(text.utf8)) }
    catch { throw CoinboxError.invalid("couldn't read the JSON as \(T.self): \(error)") }
}

/// "12.34" → 12_340 milliunits, exactly (no floating point).
func parseDollars(_ s: String) throws -> Milliunits {
    guard let d = Decimal(string: s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) else {
        throw CoinboxError.invalid("“\(s)” isn't an amount; write it like 12.34 or -5")
    }
    let m = d * 1000
    var rounded = Decimal(); var source = m
    NSDecimalRound(&rounded, &source, 0, .plain)
    return Milliunits(truncating: rounded as NSNumber)
}

/// One kind of record the CLI can list, get, put and delete as JSON.
protocol CLIEntity {
    associatedtype Value: Codable
    static var noun: String { get }
    static func list(_ c: Coinbox) throws -> [Value]
    static func get(_ c: Coinbox, _ id: String) throws -> Value?
    static func putOps(_ c: Coinbox, _ v: Value) throws -> [Op]
    static func deleteOps(_ id: String) -> [Op]
}

enum AccountEntity: CLIEntity {
    static let noun = "account"
    static func list(_ c: Coinbox) throws -> [Account] { try c.accounts() }
    static func get(_ c: Coinbox, _ id: String) throws -> Account? { try c.account(id: id) }
    static func putOps(_ c: Coinbox, _ v: Account) throws -> [Op] { try c.account(id: v.id) == nil ? Coinbox.createAccountOps(v) : [.putAccount(v)] }
    static func deleteOps(_ id: String) -> [Op] { [.deleteAccount(id: id)] }
}

enum GroupEntity: CLIEntity {
    static let noun = "category group"
    static func list(_ c: Coinbox) throws -> [CategoryGroup] { try c.categoryGroups() }
    static func get(_ c: Coinbox, _ id: String) throws -> CategoryGroup? { try c.categoryGroup(id: id) }
    static func putOps(_ c: Coinbox, _ v: CategoryGroup) throws -> [Op] { [.putCategoryGroup(v)] }
    static func deleteOps(_ id: String) -> [Op] { [.deleteCategoryGroup(id: id)] }
}

enum CategoryEntity: CLIEntity {
    static let noun = "category"
    static func list(_ c: Coinbox) throws -> [CoinboxCore.Category] { try c.categories() }
    static func get(_ c: Coinbox, _ id: String) throws -> CoinboxCore.Category? { try c.category(id: id) }
    static func putOps(_ c: Coinbox, _ v: CoinboxCore.Category) throws -> [Op] { [.putCategory(v)] }
    static func deleteOps(_ id: String) -> [Op] { [.deleteCategory(id: id)] }
}

enum PayeeEntity: CLIEntity {
    static let noun = "payee"
    static func list(_ c: Coinbox) throws -> [Payee] { try c.payees() }
    static func get(_ c: Coinbox, _ id: String) throws -> Payee? { try c.payee(id: id) }
    static func putOps(_ c: Coinbox, _ v: Payee) throws -> [Op] { [.putPayee(v)] }
    static func deleteOps(_ id: String) -> [Op] { [.deletePayee(id: id)] }
}

enum TransactionEntity: CLIEntity {
    static let noun = "transaction"
    static func list(_ c: Coinbox) throws -> [Transaction] { try c.transactions() }
    static func get(_ c: Coinbox, _ id: String) throws -> Transaction? { try c.transaction(id: id) }
    static func putOps(_ c: Coinbox, _ v: Transaction) throws -> [Op] { [.putTransaction(v)] }
    static func deleteOps(_ id: String) -> [Op] { [.deleteTransaction(id: id)] }
}

struct EntityList<E: CLIEntity>: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "list", abstract: "List every \(E.noun).") }
    @OptionGroup var global: GlobalOptions
    func run() throws { try Output.json(try E.list(try global.open())) }
}

struct EntityGet<E: CLIEntity>: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "get", abstract: "Show one \(E.noun) by id.") }
    @OptionGroup var global: GlobalOptions
    @Argument var id: String
    func run() throws {
        guard let v = try E.get(try global.open(), id) else { throw CoinboxError.notFound("\(E.noun) \(id)") }
        try Output.json(v)
    }
}

struct EntityPut<E: CLIEntity>: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "put", abstract: "Create or replace a \(E.noun) from its JSON.") }
    @OptionGroup var global: GlobalOptions
    @Option(help: "The \(E.noun) as JSON, in the shape `list` prints.") var json: String
    func run() throws {
        let c = try global.open()
        let value = try decodeJSON(E.Value.self, json)
        try c.perform(try E.putOps(c, value), author: global.author)
        try Output.json(value)
    }
}

struct EntityDelete<E: CLIEntity>: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "delete", abstract: "Delete a \(E.noun) by id (refused if it has history).") }
    @OptionGroup var global: GlobalOptions
    @Argument var id: String
    func run() throws {
        try global.open().perform(E.deleteOps(id), author: global.author)
        try Output.json(["deleted": id])
    }
}

struct AccountGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "account", abstract: "Accounts. A new credit card also gets its payment category.",
        subcommands: [EntityList<AccountEntity>.self, EntityGet<AccountEntity>.self, EntityPut<AccountEntity>.self, EntityDelete<AccountEntity>.self])
}
struct CategoryGroupGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "category-group", abstract: "Category groups.",
        subcommands: [EntityList<GroupEntity>.self, EntityGet<GroupEntity>.self, EntityPut<GroupEntity>.self, EntityDelete<GroupEntity>.self])
}
struct CategoryGroupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "category", abstract: "Categories.",
        subcommands: [EntityList<CategoryEntity>.self, EntityGet<CategoryEntity>.self, EntityPut<CategoryEntity>.self, EntityDelete<CategoryEntity>.self])
}
struct PayeeGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "payee", abstract: "Payees.",
        subcommands: [EntityList<PayeeEntity>.self, EntityGet<PayeeEntity>.self, EntityPut<PayeeEntity>.self, EntityDelete<PayeeEntity>.self])
}

struct TransactionGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "transaction", abstract: "Transactions, with splits inside.",
        subcommands: [List.self, EntityGet<TransactionEntity>.self, TransactionPut.self, EntityDelete<TransactionEntity>.self,
                      BulkApprove.self, BulkCategorize.self, BulkDelete.self, Search.self])

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "search", abstract: "Find transactions, newest first. Every given filter must match; text looks at payee, raw payee, memo, category, amount and date.")
        @OptionGroup var global: GlobalOptions
        @Option var text: String?
        @Option var account: String?
        @Option var category: String?
        @Option(help: "true or false.") var approved: Bool?
        @Option var from: String?
        @Option var to: String?
        @Flag(help: "Only transactions with no category (transfers and splits excluded).") var uncategorized = false
        func run() throws {
            try Output.json(try global.open().search(TransactionFilter(accountID: account, categoryID: category, text: text, approved: approved, from: from, to: to, uncategorized: uncategorized)))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List transactions, oldest first.")
        @OptionGroup var global: GlobalOptions
        @Option(help: "Only this account id.") var account: String?
        @Option(help: "Only on or after this date, 2026-01-31.") var since: String?
        @Option(help: "Only on or before this date.") var until: String?
        func run() throws {
            let all = try global.open().transactions(accountID: account)
            try Output.json(all.filter { (since == nil || $0.date >= since!) && (until == nil || $0.date <= until!) })
        }
    }
}

/// Like the generic put, but stamps the author (a transaction records who made it).
struct TransactionPut: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "put", abstract: "Create or replace a transaction from JSON: accountID, date, amount (milliunits, negative = outflow); everything else optional.")
    @OptionGroup var global: GlobalOptions
    @Option var json: String
    func run() throws {
        let c = try global.open()
        var t = try decodeJSON(Transaction.self, json)
        t.author = global.author
        try c.perform([.putTransaction(t)], author: global.author)
        try Output.json(t)
    }
}

struct TargetGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "target", abstract: "Spending targets.", subcommands: [List.self, Put.self, Delete.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        @OptionGroup var global: GlobalOptions
        func run() throws { try Output.json(try global.open().targets()) }
    }
    struct Put: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "put", abstract: "Set a category's target from JSON: categoryID, cadence, amount (milliunits).")
        @OptionGroup var global: GlobalOptions
        @Option var json: String
        func run() throws {
            let t = try decodeJSON(Target.self, json)
            try global.open().perform([.putTarget(t)], author: global.author)
            try Output.json(t)
        }
    }
    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete")
        @OptionGroup var global: GlobalOptions
        @Argument var categoryID: String
        func run() throws {
            try global.open().perform([.deleteTarget(categoryID: categoryID)], author: global.author)
            try Output.json(["deleted": categoryID])
        }
    }
}
