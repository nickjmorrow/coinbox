import Foundation
import GRDB

enum Applier {
    /// Applies one op and returns the op that undoes it.
    static func apply(_ op: Op, in db: Database) throws -> Op {
        switch op {
        case let .putMonthNote(n):
            let previous = try Store.monthNote(n.month, db)
            try Store.writeMonthNote(n, db)
            return previous.map(Op.putMonthNote) ?? .deleteMonthNote(month: n.month)
        case let .deleteMonthNote(month):
            guard let previous = try Store.monthNote(month, db) else { throw CoinboxError.notFound("monthNote \(month)") }
            try db.execute(sql: "DELETE FROM month_notes WHERE month = ?", arguments: [month])
            return .putMonthNote(previous)
        case let .putAccount(a):
            let previous = try Store.account(a.id, db)
            try Store.writeAccount(a, db)
            return previous.map(Op.putAccount) ?? .deleteAccount(id: a.id)
        case let .deleteAccount(id):
            guard let previous = try Store.account(id, db) else { throw CoinboxError.notFound("account \(id)") }
            let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transactions WHERE account_id = ?", arguments: [id]) ?? 0
            if n > 0 { throw CoinboxError.hasHistory("account \(id) has \(n) transactions; delete them first, or close the account instead") }
            try db.execute(sql: "DELETE FROM accounts WHERE id = ?", arguments: [id])
            return .putAccount(previous)
        case let .putCategoryGroup(g):
            let previous = try Store.group(g.id, db)
            try Store.writeGroup(g, db)
            return previous.map(Op.putCategoryGroup) ?? .deleteCategoryGroup(id: g.id)
        case let .deleteCategoryGroup(id):
            guard let previous = try Store.group(id, db) else { throw CoinboxError.notFound("category group \(id)") }
            let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE group_id = ?", arguments: [id]) ?? 0
            if n > 0 { throw CoinboxError.hasHistory("category group \(id) still has \(n) categories; move or delete them first") }
            try db.execute(sql: "DELETE FROM category_groups WHERE id = ?", arguments: [id])
            return .putCategoryGroup(previous)
        case let .putCategory(c):
            let previous = try Store.category(c.id, db)
            try Store.writeCategory(c, db)
            return previous.map(Op.putCategory) ?? .deleteCategory(id: c.id)
        case let .deleteCategory(id):
            guard let previous = try Store.category(id, db) else { throw CoinboxError.notFound("category \(id)") }
            let uses = try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM assignments WHERE category_id = ?) + (SELECT COUNT(*) FROM targets WHERE category_id = ?)
                     + (SELECT COUNT(*) FROM transactions WHERE category_id = ?) + (SELECT COUNT(*) FROM split_lines WHERE category_id = ?)
                """, arguments: [id, id, id, id]) ?? 0
            if uses > 0 { throw CoinboxError.hasHistory("category \(id) is used by assignments, a target or transactions; remove those first") }
            try db.execute(sql: "DELETE FROM categories WHERE id = ?", arguments: [id])
            return .putCategory(previous)
        case let .putPayee(p):
            let previous = try Store.payee(p.id, db)
            try Store.writePayee(p, db)
            return previous.map(Op.putPayee) ?? .deletePayee(id: p.id)
        case let .deletePayee(id):
            guard let previous = try Store.payee(id, db) else { throw CoinboxError.notFound("payee \(id)") }
            try db.execute(sql: "DELETE FROM payees WHERE id = ?", arguments: [id])
            return .putPayee(previous)
        case let .putAssignment(a):
            guard MonthKey(a.month) != nil else { throw CoinboxError.invalid("month must look like 2026-01") }
            guard let c = try Store.category(a.categoryID, db) else { throw CoinboxError.notFound("category \(a.categoryID)") }
            switch c.kind {
            case .normal, .cardPayment: break
            case .readyToAssign, .cardInterest: throw CoinboxError.invalid("\(c.name) can't be assigned money")
            }
            let previous = try Store.assignment(a.categoryID, a.month, db)
            try Store.writeAssignment(a, db)
            return previous.map(Op.putAssignment) ?? .deleteAssignment(categoryID: a.categoryID, month: a.month)
        case let .deleteAssignment(categoryID, month):
            guard let previous = try Store.assignment(categoryID, month, db) else { throw CoinboxError.notFound("assignment \(categoryID) \(month)") }
            try db.execute(sql: "DELETE FROM assignments WHERE category_id = ? AND month = ?", arguments: [categoryID, month])
            return .putAssignment(previous)
        case let .putTarget(t):
            guard try Store.category(t.categoryID, db) != nil else { throw CoinboxError.notFound("category \(t.categoryID)") }
            let previous = try Store.target(t.categoryID, db)
            try Store.writeTarget(t, db)
            return previous.map(Op.putTarget) ?? .deleteTarget(categoryID: t.categoryID)
        case let .deleteTarget(categoryID):
            guard let previous = try Store.target(categoryID, db) else { throw CoinboxError.notFound("target \(categoryID)") }
            try db.execute(sql: "DELETE FROM targets WHERE category_id = ?", arguments: [categoryID])
            return .putTarget(previous)
        case let .putTransaction(t):
            try validate(t, in: db)
            let previous = try Store.transaction(t.id, db)
            try Store.writeTransaction(t, db)
            return previous.map(Op.putTransaction) ?? .deleteTransaction(id: t.id)
        case let .deleteTransaction(id):
            guard let previous = try Store.transaction(id, db) else { throw CoinboxError.notFound("transaction \(id)") }
            try db.execute(sql: "DELETE FROM transactions WHERE id = ?", arguments: [id])
            return .putTransaction(previous)
        case let .putCardTerms(t):
            guard let a = try Store.account(t.accountID, db), a.kind == .creditCard else { throw CoinboxError.invalid("card terms belong to a credit card account") }
            guard t.aprBasisPoints >= 0, t.minimumPayment >= 0 else { throw CoinboxError.invalid("the rate and minimum can't be negative") }
            let previous = try Store.cardTerms(t.accountID, db)
            try db.execute(sql: "INSERT OR REPLACE INTO card_terms (account_id, apr_basis_points, minimum_payment) VALUES (?, ?, ?)", arguments: [t.accountID, t.aprBasisPoints, t.minimumPayment])
            return previous.map(Op.putCardTerms) ?? .deleteCardTerms(accountID: t.accountID)
        case let .deleteCardTerms(id):
            guard let previous = try Store.cardTerms(id, db) else { throw CoinboxError.notFound("card terms \(id)") }
            try db.execute(sql: "DELETE FROM card_terms WHERE account_id = ?", arguments: [id])
            return .putCardTerms(previous)
        case let .putAmazonLink(l):
            guard try Store.transaction(l.transactionID, db) != nil else { throw CoinboxError.notFound("transaction \(l.transactionID)") }
            let previous = try Store.amazonLink(l.transactionID, db)
            try db.execute(sql: "INSERT OR REPLACE INTO amazon_links (transaction_id, body) VALUES (?, ?)", arguments: [l.transactionID, try json(l)])
            return previous.map(Op.putAmazonLink) ?? .deleteAmazonLink(transactionID: l.transactionID)
        case let .deleteAmazonLink(id):
            guard let previous = try Store.amazonLink(id, db) else { throw CoinboxError.notFound("amazon link \(id)") }
            try db.execute(sql: "DELETE FROM amazon_links WHERE transaction_id = ?", arguments: [id])
            return .putAmazonLink(previous)
        case let .putRule(r):
            let previous = try Store.rule(r.id, db)
            try Store.writeRule(r, db)
            return previous.map(Op.putRule) ?? .deleteRule(id: r.id)
        case let .deleteRule(id):
            guard let previous = try Store.rule(id, db) else { throw CoinboxError.notFound("rule \(id)") }
            try db.execute(sql: "DELETE FROM rules WHERE id = ?", arguments: [id])
            return .putRule(previous)
        case let .batch(ops):
            var inverses: [Op] = []
            for o in ops { inverses.append(try apply(o, in: db)) }
            return .batch(inverses.reversed())
        }
    }

    /// Refuses a transaction the budget math can't make sense of.
    static func validate(_ t: Transaction, in db: Database) throws {
        guard MonthKey.isValidDate(t.date) else { throw CoinboxError.invalid("date must look like 2026-01-31") }
        guard try Store.account(t.accountID, db) != nil else { throw CoinboxError.notFound("account \(t.accountID)") }
        if let p = t.payeeID, try Store.payee(p, db) == nil { throw CoinboxError.notFound("payee \(p)") }
        func check(categoryID: String, amount: Milliunits) throws {
            guard let c = try Store.category(categoryID, db) else { throw CoinboxError.notFound("category \(categoryID)") }
            if c.kind == .readyToAssign && amount < 0 { throw CoinboxError.invalid("an outflow can't be categorized to Ready to Assign") }
        }
        if t.splits.isEmpty {
            if let c = t.categoryID { try check(categoryID: c, amount: t.amount) }
        } else {
            guard t.splits.count >= 2 else { throw CoinboxError.invalid("a split needs at least two lines") }
            guard t.categoryID == nil else { throw CoinboxError.invalid("a split transaction has no category of its own") }
            guard t.splits.reduce(0, { $0 + $1.amount }) == t.amount else { throw CoinboxError.invalid("split lines must add up to the transaction amount") }
            for s in t.splits { try check(categoryID: s.categoryID, amount: s.amount) }
        }
    }
}
