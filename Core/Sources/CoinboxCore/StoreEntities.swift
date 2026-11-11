import Foundation
import GRDB

func json<T: Encodable>(_ v: T) throws -> String {
    let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
    return String(decoding: try e.encode(v), as: UTF8.self)
}

func unjson<T: Decodable>(_ s: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(s.utf8)) }

extension Store {
    // MARK: accounts
    static func decodeAccount(_ r: Row) -> Account {
        Account(id: r["id"], name: r["name"], kind: AccountKind(rawValue: r["kind"]) ?? .checking, onBudget: r["on_budget"], closed: r["closed"],
                note: r["note"], simplefinID: r["simplefin_id"], ynabID: r["ynab_id"], lastReconciledDate: r["last_reconciled_date"],
                lastReconciledBalance: r["last_reconciled_balance"])
    }

    static func account(_ id: String, _ db: Database) throws -> Account? {
        try Row.fetchOne(db, sql: "SELECT * FROM accounts WHERE id = ?", arguments: [id]).map(decodeAccount)
    }

    static func writeAccount(_ a: Account, _ db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO accounts (id, name, kind, on_budget, closed, note, simplefin_id, ynab_id, last_reconciled_date, last_reconciled_balance)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [a.id, a.name, a.kind.rawValue, a.onBudget, a.closed, a.note, a.simplefinID, a.ynabID, a.lastReconciledDate, a.lastReconciledBalance])
    }

    // MARK: groups
    static func decodeGroup(_ r: Row) -> CategoryGroup { CategoryGroup(id: r["id"], name: r["name"], order: r["position"], hidden: r["hidden"]) }

    static func group(_ id: String, _ db: Database) throws -> CategoryGroup? {
        try Row.fetchOne(db, sql: "SELECT * FROM category_groups WHERE id = ?", arguments: [id]).map(decodeGroup)
    }

    static func writeGroup(_ g: CategoryGroup, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO category_groups (id, name, position, hidden) VALUES (?, ?, ?, ?)", arguments: [g.id, g.name, g.order, g.hidden])
    }

    // MARK: categories
    static func decodeCategory(_ r: Row) -> Category {
        let kind: CategoryKind
        switch r["kind"] as String {
        case "cardPayment": kind = .cardPayment(accountID: r["card_account_id"] ?? "")
        case "readyToAssign": kind = .readyToAssign
        case "cardInterest": kind = .cardInterest
        default: kind = .normal
        }
        return Category(id: r["id"], groupID: r["group_id"], name: r["name"], order: r["position"], hidden: r["hidden"], note: r["note"], kind: kind, ynabID: r["ynab_id"])
    }

    static func category(_ id: String, _ db: Database) throws -> Category? {
        try Row.fetchOne(db, sql: "SELECT * FROM categories WHERE id = ?", arguments: [id]).map(decodeCategory)
    }

    static func writeCategory(_ c: Category, _ db: Database) throws {
        let kind: String, card: String?
        switch c.kind {
        case .normal: kind = "normal"; card = nil
        case let .cardPayment(accountID): kind = "cardPayment"; card = accountID
        case .readyToAssign: kind = "readyToAssign"; card = nil
        case .cardInterest: kind = "cardInterest"; card = nil
        }
        try db.execute(sql: """
            INSERT INTO categories (id, group_id, name, position, hidden, note, kind, card_account_id, ynab_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET group_id = excluded.group_id, name = excluded.name, position = excluded.position, hidden = excluded.hidden,
              note = excluded.note, kind = excluded.kind, card_account_id = excluded.card_account_id, ynab_id = excluded.ynab_id
            """, arguments: [c.id, c.groupID, c.name, c.order, c.hidden, c.note, kind, card, c.ynabID])
    }

    // MARK: payees
    static func decodePayee(_ r: Row) -> Payee {
        Payee(id: r["id"], name: r["name"], defaultCategoryID: r["default_category_id"], defaultLocked: r["default_locked"], transferAccountID: r["transfer_account_id"])
    }

    static func payee(_ id: String, _ db: Database) throws -> Payee? {
        try Row.fetchOne(db, sql: "SELECT * FROM payees WHERE id = ?", arguments: [id]).map(decodePayee)
    }

    static func writePayee(_ p: Payee, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO payees (id, name, default_category_id, default_locked, transfer_account_id) VALUES (?, ?, ?, ?, ?)",
                       arguments: [p.id, p.name, p.defaultCategoryID, p.defaultLocked, p.transferAccountID])
    }

    // MARK: assignments and targets
    static func assignment(_ categoryID: String, _ month: String, _ db: Database) throws -> Assignment? {
        try Row.fetchOne(db, sql: "SELECT * FROM assignments WHERE category_id = ? AND month = ?", arguments: [categoryID, month])
            .map { Assignment(categoryID: $0["category_id"], month: $0["month"], amount: $0["amount"]) }
    }

    static func writeAssignment(_ a: Assignment, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO assignments (category_id, month, amount) VALUES (?, ?, ?)", arguments: [a.categoryID, a.month, a.amount])
    }

    static func target(_ categoryID: String, _ db: Database) throws -> Target? {
        try Row.fetchOne(db, sql: "SELECT * FROM targets WHERE category_id = ?", arguments: [categoryID]).map(decodeTarget)
    }

    static func decodeTarget(_ r: Row) throws -> Target { Target(categoryID: r["category_id"], cadence: try unjson(r["cadence"]), amount: r["amount"]) }

    static func writeTarget(_ t: Target, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO targets (category_id, cadence, amount) VALUES (?, ?, ?)", arguments: [t.categoryID, try json(t.cadence), t.amount])
    }

    // MARK: transactions
    static func decodeTransaction(_ r: Row, splits: [SplitLine]) -> Transaction {
        Transaction(id: r["id"], accountID: r["account_id"], date: r["date"], payeeID: r["payee_id"], categoryID: r["category_id"], memo: r["memo"],
                    amount: r["amount"], cleared: ClearedState(rawValue: r["cleared"]) ?? .uncleared, approved: r["approved"],
                    transferPairID: r["transfer_pair_id"], bankImportID: r["bank_import_id"], ynabID: r["ynab_id"], rawPayee: r["raw_payee"], pending: r["pending"],
                    author: Author(rawValue: r["author"]) ?? .importer, splits: splits)
    }

    static func splits(of id: String, _ db: Database) throws -> [SplitLine] {
        try Row.fetchAll(db, sql: "SELECT * FROM split_lines WHERE transaction_id = ? ORDER BY position", arguments: [id])
            .map { SplitLine(categoryID: $0["category_id"], amount: $0["amount"], memo: $0["memo"]) }
    }

    static func transaction(_ id: String, _ db: Database) throws -> Transaction? {
        try Row.fetchOne(db, sql: "SELECT * FROM transactions WHERE id = ?", arguments: [id]).map { decodeTransaction($0, splits: try splits(of: id, db)) }
    }

    static func writeTransaction(_ t: Transaction, _ db: Database) throws {
        try db.execute(sql: "DELETE FROM transactions WHERE id = ?", arguments: [t.id])     // cascades the old split lines
        try db.execute(sql: """
            INSERT INTO transactions (id, account_id, date, payee_id, category_id, memo, amount, cleared, approved, transfer_pair_id, bank_import_id, ynab_id, raw_payee, pending, author)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [t.id, t.accountID, t.date, t.payeeID, t.categoryID, t.memo, t.amount, t.cleared.rawValue, t.approved, t.transferPairID,
                              t.bankImportID, t.ynabID, t.rawPayee, t.pending, t.author.rawValue])
        for (i, s) in t.splits.enumerated() {
            try db.execute(sql: "INSERT INTO split_lines (transaction_id, position, category_id, amount, memo) VALUES (?, ?, ?, ?, ?)",
                           arguments: [t.id, i, s.categoryID, s.amount, s.memo])
        }
    }

    /// Every transaction with its splits, in two queries.
    static func allTransactions(accountID: String?, _ db: Database) throws -> [Transaction] {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM transactions WHERE (? IS NULL OR account_id = ?) ORDER BY date, id", arguments: [accountID, accountID])
        var splitsByID: [String: [SplitLine]] = [:]
        for r in try Row.fetchAll(db, sql: "SELECT * FROM split_lines ORDER BY transaction_id, position") {
            splitsByID[r["transaction_id"], default: []].append(SplitLine(categoryID: r["category_id"], amount: r["amount"], memo: r["memo"]))
        }
        return rows.map { decodeTransaction($0, splits: splitsByID[$0["id"] as String] ?? []) }
    }
}

extension Store {
    static func decodeRule(_ r: Row) throws -> Rule { try unjson(r["body"]) }

    static func rule(_ id: String, _ db: Database) throws -> Rule? {
        try Row.fetchOne(db, sql: "SELECT * FROM rules WHERE id = ?", arguments: [id]).map(decodeRule)
    }

    static func writeRule(_ r: Rule, _ db: Database) throws {
        try db.execute(sql: "INSERT OR REPLACE INTO rules (id, position, body) VALUES (?, ?, ?)", arguments: [r.id, r.order, try json(r)])
    }
}

extension Store {
    static func cardTerms(_ id: String, _ db: Database) throws -> CardTerms? {
        try Row.fetchOne(db, sql: "SELECT * FROM card_terms WHERE account_id = ?", arguments: [id]).map { CardTerms(accountID: $0["account_id"], aprBasisPoints: $0["apr_basis_points"], minimumPayment: $0["minimum_payment"]) }
    }

    static func amazonLink(_ id: String, _ db: Database) throws -> AmazonLink? {
        try Row.fetchOne(db, sql: "SELECT * FROM amazon_links WHERE transaction_id = ?", arguments: [id]).map { try unjson($0["body"]) }
    }
}

extension Coinbox {
    public func cardTerms() throws -> [CardTerms] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM card_terms ORDER BY account_id").map { CardTerms(accountID: $0["account_id"], aprBasisPoints: $0["apr_basis_points"], minimumPayment: $0["minimum_payment"]) } }
    }
    public func amazonLink(transactionID: String) throws -> AmazonLink? { try db.read { try Store.amazonLink(transactionID, $0) } }
    public func amazonLinks() throws -> [AmazonLink] { try db.read { try Row.fetchAll($0, sql: "SELECT body FROM amazon_links ORDER BY transaction_id").map { try unjson($0["body"]) } } }

    public func rule(id: String) throws -> Rule? { try db.read { try Store.rule(id, $0) } }
    public func rules() throws -> [Rule] { try db.read { try Row.fetchAll($0, sql: "SELECT * FROM rules ORDER BY position, id").map(Store.decodeRule) } }
    public func account(id: String) throws -> Account? { try db.read { try Store.account(id, $0) } }
    public func categoryGroup(id: String) throws -> CategoryGroup? { try db.read { try Store.group(id, $0) } }
    public func category(id: String) throws -> Category? { try db.read { try Store.category(id, $0) } }
    public func payee(id: String) throws -> Payee? { try db.read { try Store.payee(id, $0) } }
    public func assignment(categoryID: String, month: String) throws -> Assignment? { try db.read { try Store.assignment(categoryID, month, $0) } }
    public func target(categoryID: String) throws -> Target? { try db.read { try Store.target(categoryID, $0) } }
    public func transaction(id: String) throws -> Transaction? { try db.read { try Store.transaction(id, $0) } }

    public func accounts() throws -> [Account] { try db.read { try Row.fetchAll($0, sql: "SELECT * FROM accounts ORDER BY name, id").map(Store.decodeAccount) } }
    public func categoryGroups() throws -> [CategoryGroup] { try db.read { try Row.fetchAll($0, sql: "SELECT * FROM category_groups ORDER BY position, name, id").map(Store.decodeGroup) } }
    public func categories() throws -> [Category] { try db.read { try Row.fetchAll($0, sql: "SELECT * FROM categories ORDER BY position, name, id").map(Store.decodeCategory) } }
    public func payees() throws -> [Payee] { try db.read { try Row.fetchAll($0, sql: "SELECT * FROM payees ORDER BY name, id").map(Store.decodePayee) } }
    public func assignments() throws -> [Assignment] {
        try db.read { try Row.fetchAll($0, sql: "SELECT * FROM assignments ORDER BY month, category_id").map { Assignment(categoryID: $0["category_id"], month: $0["month"], amount: $0["amount"]) } }
    }
    public func targets() throws -> [Target] { try db.read { try Row.fetchAll($0, sql: "SELECT * FROM targets ORDER BY category_id").map(Store.decodeTarget) } }
    public func transactions(accountID: String? = nil) throws -> [Transaction] { try db.read { try Store.allTransactions(accountID: accountID, $0) } }
}
