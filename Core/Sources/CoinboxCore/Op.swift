import Foundation

/// Every change to a Coinbox database is one of these. They are logged, replayed by sync and inverted by undo.
public indirect enum Op: Codable, Sendable, Equatable {
    case putMonthNote(MonthNote)
    case deleteMonthNote(month: String)
    case putAccount(Account)
    case deleteAccount(id: String)
    case putCategoryGroup(CategoryGroup)
    case deleteCategoryGroup(id: String)
    case putCategory(Category)
    case deleteCategory(id: String)
    case putPayee(Payee)
    case deletePayee(id: String)
    case putAssignment(Assignment)
    case deleteAssignment(categoryID: String, month: String)
    case putTarget(Target)
    case deleteTarget(categoryID: String)
    case putCardTerms(CardTerms)
    case deleteCardTerms(accountID: String)
    case putAmazonLink(AmazonLink)
    case deleteAmazonLink(transactionID: String)
    case putRule(Rule)
    case deleteRule(id: String)
    case putTransaction(Transaction)
    case deleteTransaction(id: String)
    case batch([Op])

    var kind: String { Mirror(reflecting: self).children.first?.label ?? "\(self)" }

    /// A short description in plain English, for the changes list.
    var summary: String {
        switch self {
        case let .putMonthNote(n): return "Saved note for \(n.month)"
        case let .deleteMonthNote(month): return "Removed note for \(month)"
        case let .putAccount(a): return "Saved account “\(a.name)”"
        case .deleteAccount: return "Deleted an account"
        case let .putCategoryGroup(g): return "Saved category group “\(g.name)”"
        case .deleteCategoryGroup: return "Deleted a category group"
        case let .putCategory(c): return "Saved category “\(c.name)”"
        case .deleteCategory: return "Deleted a category"
        case let .putPayee(p): return "Saved payee “\(p.name)”"
        case .deletePayee: return "Deleted a payee"
        case let .putAssignment(a): return "Assigned \(Money.format(a.amount)) in \(a.month)"
        case let .deleteAssignment(_, month): return "Cleared an assignment in \(month)"
        case .putTarget: return "Saved a target"
        case .deleteTarget: return "Removed a target"
        case let .putTransaction(t): return "Saved transaction \(Money.format(t.amount)) on \(t.date)"
        case .deleteTransaction: return "Deleted a transaction"
        case .putCardTerms: return "Saved a card's rate and minimum"
        case .deleteCardTerms: return "Removed a card's rate"
        case .putAmazonLink: return "Split an Amazon charge"
        case .deleteAmazonLink: return "Removed an Amazon split"
        case let .putRule(r): return "Saved rule “\(r.name)”"
        case .deleteRule: return "Deleted a rule"
        case let .batch(ops):
            return ops.prefix(4).map(\.summary).joined(separator: "; ") + (ops.count > 4 ? "; and \(ops.count - 4) more" : "")
        }
    }

    /// Entities this op writes, as "kind:id" keys; used to detect later edits that block an undo.
    var entityKeys: Set<String> {
        switch self {
        case let .putMonthNote(n): return ["monthNote:\(n.month)"]
        case let .deleteMonthNote(month): return ["monthNote:\(month)"]
        case let .putAccount(a): return ["account:\(a.id)"]
        case let .deleteAccount(id): return ["account:\(id)"]
        case let .putCategoryGroup(g): return ["group:\(g.id)"]
        case let .deleteCategoryGroup(id): return ["group:\(id)"]
        case let .putCategory(c): return ["category:\(c.id)"]
        case let .deleteCategory(id): return ["category:\(id)"]
        case let .putPayee(p): return ["payee:\(p.id)"]
        case let .deletePayee(id): return ["payee:\(id)"]
        case let .putAssignment(a): return ["assignment:\(a.categoryID)|\(a.month)"]
        case let .deleteAssignment(categoryID, month): return ["assignment:\(categoryID)|\(month)"]
        case let .putTarget(t): return ["target:\(t.categoryID)"]
        case let .deleteTarget(categoryID): return ["target:\(categoryID)"]
        case let .putTransaction(t): return ["transaction:\(t.id)"]
        case let .deleteTransaction(id): return ["transaction:\(id)"]
        case let .putCardTerms(t): return ["cardTerms:\(t.accountID)"]
        case let .deleteCardTerms(id): return ["cardTerms:\(id)"]
        case let .putAmazonLink(l): return ["amazon:\(l.transactionID)"]
        case let .deleteAmazonLink(id): return ["amazon:\(id)"]
        case let .putRule(r): return ["rule:\(r.id)"]
        case let .deleteRule(id): return ["rule:\(id)"]
        case let .batch(ops): return ops.reduce(into: Set<String>()) { $0.formUnion($1.entityKeys) }
        }
    }
}

public enum CoinboxError: Error, Equatable {
    case notFound(String)
    case invalid(String)
    case hasHistory(String)
}

extension CoinboxError {
    /// A sentence an agent or person can act on.
    public var message: String {
        switch self {
        case let .notFound(what): return "not found: \(what)"
        case let .invalid(why): return why
        case let .hasHistory(what): return what
        }
    }
}
