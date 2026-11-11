import Foundation

public enum AccountKind: String, Codable, Sendable, CaseIterable { case checking, savings, cash, creditCard, mortgage, loan, asset }

public struct Account: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var kind: AccountKind
    /// False for tracking accounts (mortgage, loan, asset).
    public var onBudget: Bool
    public var closed: Bool
    public var note: String?
    public var simplefinID: String?
    public var ynabID: String?
    public var lastReconciledDate: String?
    public var lastReconciledBalance: Milliunits?

    public init(id: String = UUID().uuidString.lowercased(), name: String, kind: AccountKind = .checking, onBudget: Bool = true, closed: Bool = false,
                note: String? = nil, simplefinID: String? = nil, ynabID: String? = nil, lastReconciledDate: String? = nil, lastReconciledBalance: Milliunits? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.onBudget = onBudget; self.closed = closed; self.note = note
        self.simplefinID = simplefinID; self.ynabID = ynabID; self.lastReconciledDate = lastReconciledDate; self.lastReconciledBalance = lastReconciledBalance
    }

    /// Lenient: only `name` is required; the rest take their usual defaults.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let kind = try c.decodeIfPresent(AccountKind.self, forKey: .kind) ?? .checking
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased(), name: try c.decode(String.self, forKey: .name),
                  kind: kind, onBudget: try c.decodeIfPresent(Bool.self, forKey: .onBudget) ?? ![.mortgage, .loan, .asset].contains(kind),
                  closed: try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false, note: try c.decodeIfPresent(String.self, forKey: .note),
                  simplefinID: try c.decodeIfPresent(String.self, forKey: .simplefinID), ynabID: try c.decodeIfPresent(String.self, forKey: .ynabID),
                  lastReconciledDate: try c.decodeIfPresent(String.self, forKey: .lastReconciledDate),
                  lastReconciledBalance: try c.decodeIfPresent(Milliunits.self, forKey: .lastReconciledBalance))
    }
}

public struct CategoryGroup: Codable, Sendable, Equatable {
    public static let inflowID = "inflow"
    public static let cardPaymentsID = "card-payments"

    public var id: String
    public var name: String
    public var order: Int
    public var hidden: Bool

    public init(id: String = UUID().uuidString.lowercased(), name: String, order: Int = 0, hidden: Bool = false) {
        self.id = id; self.name = name; self.order = order; self.hidden = hidden
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased(), name: try c.decode(String.self, forKey: .name),
                  order: try c.decodeIfPresent(Int.self, forKey: .order) ?? 0, hidden: try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false)
    }
}

/// JSON: {"type": "normal"}, {"type": "cardPayment", "accountID": "…"}, {"type": "readyToAssign"}, {"type": "cardInterest"}.
public enum CategoryKind: Codable, Sendable, Equatable {
    case normal
    case cardPayment(accountID: String)
    case readyToAssign
    case cardInterest

    private enum Keys: String, CodingKey { case type, accountID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "normal": self = .normal
        case "cardPayment": self = .cardPayment(accountID: try c.decode(String.self, forKey: .accountID))
        case "readyToAssign": self = .readyToAssign
        case "cardInterest": self = .cardInterest
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown category kind \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .normal: try c.encode("normal", forKey: .type)
        case let .cardPayment(accountID): try c.encode("cardPayment", forKey: .type); try c.encode(accountID, forKey: .accountID)
        case .readyToAssign: try c.encode("readyToAssign", forKey: .type)
        case .cardInterest: try c.encode("cardInterest", forKey: .type)
        }
    }
}

public struct Category: Codable, Sendable, Equatable {
    public static let readyToAssignID = "ready-to-assign"
    public static let cardInterestID = "card-interest"

    public var id: String
    public var groupID: String
    public var name: String
    public var order: Int
    public var hidden: Bool
    public var note: String?
    public var kind: CategoryKind
    public var ynabID: String?

    public init(id: String = UUID().uuidString.lowercased(), groupID: String, name: String, order: Int = 0, hidden: Bool = false,
                note: String? = nil, kind: CategoryKind = .normal, ynabID: String? = nil) {
        self.id = id; self.groupID = groupID; self.name = name; self.order = order; self.hidden = hidden
        self.note = note; self.kind = kind; self.ynabID = ynabID
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased(), groupID: try c.decode(String.self, forKey: .groupID),
                  name: try c.decode(String.self, forKey: .name), order: try c.decodeIfPresent(Int.self, forKey: .order) ?? 0,
                  hidden: try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false, note: try c.decodeIfPresent(String.self, forKey: .note),
                  kind: try c.decodeIfPresent(CategoryKind.self, forKey: .kind) ?? .normal, ynabID: try c.decodeIfPresent(String.self, forKey: .ynabID))
    }
}

public struct Payee: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var defaultCategoryID: String?
    /// A locked default never changes.
    public var defaultLocked: Bool
    public var transferAccountID: String?

    public init(id: String = UUID().uuidString.lowercased(), name: String, defaultCategoryID: String? = nil, defaultLocked: Bool = false, transferAccountID: String? = nil) {
        self.id = id; self.name = name; self.defaultCategoryID = defaultCategoryID; self.defaultLocked = defaultLocked; self.transferAccountID = transferAccountID
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased(), name: try c.decode(String.self, forKey: .name),
                  defaultCategoryID: try c.decodeIfPresent(String.self, forKey: .defaultCategoryID),
                  defaultLocked: try c.decodeIfPresent(Bool.self, forKey: .defaultLocked) ?? false,
                  transferAccountID: try c.decodeIfPresent(String.self, forKey: .transferAccountID))
    }
}

/// Money given a job: (category, month) → amount. Activity and Available are computed, never stored.
public struct Assignment: Codable, Sendable, Equatable {
    public var categoryID: String
    public var month: String
    public var amount: Milliunits

    public init(categoryID: String, month: String, amount: Milliunits) { self.categoryID = categoryID; self.month = month; self.amount = amount }
}

/// JSON: {"type": "weekly", "isoWeekday": 1}, {"type": "monthly", "day": 1}, {"type": "yearly", "month": 12, "day": 15},
/// {"type": "byDate", "date": "2026-06-30"}, {"type": "everyMonths", "n": 3, "firstDue": "2026-03-31"}.
public enum Cadence: Codable, Sendable, Equatable {
    /// `isoWeekday`: 1 = Monday ... 7 = Sunday.
    case weekly(isoWeekday: Int)
    case monthly(day: Int)
    case yearly(month: Int, day: Int)
    /// A due date, "YYYY-MM-DD".
    case byDate(String)
    /// Due every `n` months starting at `firstDue`.
    case everyMonths(n: Int, firstDue: String)

    private enum Keys: String, CodingKey { case type, isoWeekday, day, month, date, n, firstDue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "weekly": self = .weekly(isoWeekday: try c.decode(Int.self, forKey: .isoWeekday))
        case "monthly": self = .monthly(day: try c.decode(Int.self, forKey: .day))
        case "yearly": self = .yearly(month: try c.decode(Int.self, forKey: .month), day: try c.decode(Int.self, forKey: .day))
        case "byDate": self = .byDate(try c.decode(String.self, forKey: .date))
        case "everyMonths": self = .everyMonths(n: try c.decode(Int.self, forKey: .n), firstDue: try c.decode(String.self, forKey: .firstDue))
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown cadence \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .weekly(w): try c.encode("weekly", forKey: .type); try c.encode(w, forKey: .isoWeekday)
        case let .monthly(d): try c.encode("monthly", forKey: .type); try c.encode(d, forKey: .day)
        case let .yearly(m, d): try c.encode("yearly", forKey: .type); try c.encode(m, forKey: .month); try c.encode(d, forKey: .day)
        case let .byDate(d): try c.encode("byDate", forKey: .type); try c.encode(d, forKey: .date)
        case let .everyMonths(n, f): try c.encode("everyMonths", forKey: .type); try c.encode(n, forKey: .n); try c.encode(f, forKey: .firstDue)
        }
    }
}

public struct Target: Codable, Sendable, Equatable {
    public var categoryID: String
    public var cadence: Cadence
    public var amount: Milliunits

    public init(categoryID: String, cadence: Cadence, amount: Milliunits) { self.categoryID = categoryID; self.cadence = cadence; self.amount = amount }
}

public enum ClearedState: String, Codable, Sendable { case uncleared, cleared, reconciled }

public struct SplitLine: Codable, Sendable, Equatable {
    public var categoryID: String
    public var amount: Milliunits
    public var memo: String?

    public init(categoryID: String, amount: Milliunits, memo: String? = nil) { self.categoryID = categoryID; self.amount = amount; self.memo = memo }
}

public struct Transaction: Codable, Sendable, Equatable {
    public var id: String
    public var accountID: String
    /// "YYYY-MM-DD".
    public var date: String
    public var payeeID: String?
    /// Nil for transfers between on-budget accounts, split parents and uncategorized transactions.
    public var categoryID: String?
    public var memo: String?
    public var amount: Milliunits
    public var cleared: ClearedState
    public var approved: Bool
    public var transferPairID: String?
    public var bankImportID: String?
    public var ynabID: String?
    /// The bank's own text for the payee, before any renaming; what rules match on.
    public var rawPayee: String?
    public var pending: Bool
    public var author: Author
    public var splits: [SplitLine]

    public init(id: String = UUID().uuidString.lowercased(), accountID: String, date: String, payeeID: String? = nil, categoryID: String? = nil,
                memo: String? = nil, amount: Milliunits, cleared: ClearedState = .uncleared, approved: Bool = true, transferPairID: String? = nil,
                bankImportID: String? = nil, ynabID: String? = nil, rawPayee: String? = nil, pending: Bool = false, author: Author = .mac, splits: [SplitLine] = []) {
        self.id = id; self.accountID = accountID; self.date = date; self.payeeID = payeeID; self.categoryID = categoryID; self.memo = memo
        self.amount = amount; self.cleared = cleared; self.approved = approved; self.transferPairID = transferPairID
        self.bankImportID = bankImportID; self.ynabID = ynabID; self.rawPayee = rawPayee; self.pending = pending; self.author = author; self.splits = splits
    }

    /// Lenient: `accountID`, `date` and `amount` are required; everything else has a default.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased(), accountID: try c.decode(String.self, forKey: .accountID),
                  date: try c.decode(String.self, forKey: .date), payeeID: try c.decodeIfPresent(String.self, forKey: .payeeID),
                  categoryID: try c.decodeIfPresent(String.self, forKey: .categoryID), memo: try c.decodeIfPresent(String.self, forKey: .memo),
                  amount: try c.decode(Milliunits.self, forKey: .amount), cleared: try c.decodeIfPresent(ClearedState.self, forKey: .cleared) ?? .uncleared,
                  approved: try c.decodeIfPresent(Bool.self, forKey: .approved) ?? true, transferPairID: try c.decodeIfPresent(String.self, forKey: .transferPairID),
                  bankImportID: try c.decodeIfPresent(String.self, forKey: .bankImportID), ynabID: try c.decodeIfPresent(String.self, forKey: .ynabID),
                  rawPayee: try c.decodeIfPresent(String.self, forKey: .rawPayee), pending: try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false,
                  author: try c.decodeIfPresent(Author.self, forKey: .author) ?? .mac, splits: try c.decodeIfPresent([SplitLine].self, forKey: .splits) ?? [])
    }
}
