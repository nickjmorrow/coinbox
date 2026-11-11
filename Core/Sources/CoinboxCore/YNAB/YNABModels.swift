import Foundation

// YNAB API v1 response shapes, trimmed to what the import reads. Decoded with `.convertFromSnakeCase`, so `category_group_id` is `categoryGroupId`.

public struct YNABAccount: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var type: String
    public var onBudget: Bool
    public var closed: Bool
    public var note: String?
    public var balance: Int64
    public var deleted: Bool

    public init(id: String, name: String, type: String, onBudget: Bool = true, closed: Bool = false, note: String? = nil, balance: Int64 = 0, deleted: Bool = false) {
        self.id = id; self.name = name; self.type = type; self.onBudget = onBudget; self.closed = closed; self.note = note; self.balance = balance; self.deleted = deleted
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); type = try c.decode(String.self, forKey: .type)
        onBudget = try c.decodeIfPresent(Bool.self, forKey: .onBudget) ?? true; closed = try c.decodeIfPresent(Bool.self, forKey: .closed) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note); balance = try c.decodeIfPresent(Int64.self, forKey: .balance) ?? 0
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
    private enum Keys: String, CodingKey { case id, name, type, onBudget, closed, note, balance, deleted }
}

public struct YNABPayee: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var transferAccountId: String?
    public var deleted: Bool

    public init(id: String, name: String, transferAccountId: String? = nil, deleted: Bool = false) {
        self.id = id; self.name = name; self.transferAccountId = transferAccountId; self.deleted = deleted
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        transferAccountId = try c.decodeIfPresent(String.self, forKey: .transferAccountId); deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
    private enum Keys: String, CodingKey { case id, name, transferAccountId, deleted }
}

public struct YNABCategory: Codable, Sendable, Equatable {
    public var id: String
    public var categoryGroupId: String
    public var name: String
    public var hidden: Bool
    public var note: String?
    public var deleted: Bool
    public var goalType: String?
    public var goalDay: Int?
    public var goalCadence: Int?
    public var goalCadenceFrequency: Int?
    public var goalTarget: Int64?
    public var goalTargetDate: String?

    public init(id: String, categoryGroupId: String, name: String, hidden: Bool = false, note: String? = nil, deleted: Bool = false, goalType: String? = nil,
                goalDay: Int? = nil, goalCadence: Int? = nil, goalCadenceFrequency: Int? = nil, goalTarget: Int64? = nil, goalTargetDate: String? = nil) {
        self.id = id; self.categoryGroupId = categoryGroupId; self.name = name; self.hidden = hidden; self.note = note; self.deleted = deleted
        self.goalType = goalType; self.goalDay = goalDay; self.goalCadence = goalCadence; self.goalCadenceFrequency = goalCadenceFrequency
        self.goalTarget = goalTarget; self.goalTargetDate = goalTargetDate
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); categoryGroupId = try c.decode(String.self, forKey: .categoryGroupId); name = try c.decode(String.self, forKey: .name)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false; note = try c.decodeIfPresent(String.self, forKey: .note)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false; goalType = try c.decodeIfPresent(String.self, forKey: .goalType)
        goalDay = try c.decodeIfPresent(Int.self, forKey: .goalDay); goalCadence = try c.decodeIfPresent(Int.self, forKey: .goalCadence)
        goalCadenceFrequency = try c.decodeIfPresent(Int.self, forKey: .goalCadenceFrequency); goalTarget = try c.decodeIfPresent(Int64.self, forKey: .goalTarget)
        goalTargetDate = try c.decodeIfPresent(String.self, forKey: .goalTargetDate)
    }
    private enum Keys: String, CodingKey { case id, categoryGroupId, name, hidden, note, deleted, goalType, goalDay, goalCadence, goalCadenceFrequency, goalTarget, goalTargetDate }
}

public struct YNABGroup: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var hidden: Bool
    public var deleted: Bool
    public var categories: [YNABCategory]

    public init(id: String, name: String, hidden: Bool = false, deleted: Bool = false, categories: [YNABCategory] = []) {
        self.id = id; self.name = name; self.hidden = hidden; self.deleted = deleted; self.categories = categories
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false; deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        categories = try c.decodeIfPresent([YNABCategory].self, forKey: .categories) ?? []
    }
    private enum Keys: String, CodingKey { case id, name, hidden, deleted, categories }
}

public struct YNABMonthCategory: Codable, Sendable, Equatable {
    public var id: String
    public var budgeted: Int64
    public var activity: Int64
    public var balance: Int64

    public init(id: String, budgeted: Int64, activity: Int64, balance: Int64) { self.id = id; self.budgeted = budgeted; self.activity = activity; self.balance = balance }
}

public struct YNABMonth: Codable, Sendable, Equatable {
    /// First day of the month, "2026-01-01".
    public var month: String
    public var note: String?
    public var toBeBudgeted: Int64
    public var categories: [YNABMonthCategory]

    public init(month: String, note: String? = nil, toBeBudgeted: Int64 = 0, categories: [YNABMonthCategory] = []) {
        self.month = month; self.note = note; self.toBeBudgeted = toBeBudgeted; self.categories = categories
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        month = try c.decode(String.self, forKey: .month); note = try c.decodeIfPresent(String.self, forKey: .note)
        toBeBudgeted = try c.decodeIfPresent(Int64.self, forKey: .toBeBudgeted) ?? 0
        categories = try c.decodeIfPresent([YNABMonthCategory].self, forKey: .categories) ?? []
    }
    private enum Keys: String, CodingKey { case month, note, toBeBudgeted, categories }

    public var key: MonthKey? { MonthKey(String(month.prefix(7))) }
}

public struct YNABSubtransaction: Codable, Sendable, Equatable {
    public var id: String
    public var amount: Int64
    public var memo: String?
    public var categoryId: String?
    public var deleted: Bool

    public init(id: String, amount: Int64, memo: String? = nil, categoryId: String? = nil, deleted: Bool = false) {
        self.id = id; self.amount = amount; self.memo = memo; self.categoryId = categoryId; self.deleted = deleted
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); amount = try c.decode(Int64.self, forKey: .amount); memo = try c.decodeIfPresent(String.self, forKey: .memo)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId); deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }
    private enum Keys: String, CodingKey { case id, amount, memo, categoryId, deleted }
}

public struct YNABTransaction: Codable, Sendable, Equatable {
    public var id: String
    public var date: String
    public var amount: Int64
    public var memo: String?
    public var cleared: String
    public var approved: Bool
    public var accountId: String
    public var payeeId: String?
    public var categoryId: String?
    public var transferAccountId: String?
    public var transferTransactionId: String?
    public var importPayeeName: String?
    public var deleted: Bool
    public var subtransactions: [YNABSubtransaction]

    public init(id: String, date: String, amount: Int64, memo: String? = nil, cleared: String = "cleared", approved: Bool = true, accountId: String, payeeId: String? = nil,
                categoryId: String? = nil, transferAccountId: String? = nil, transferTransactionId: String? = nil, importPayeeName: String? = nil, deleted: Bool = false, subtransactions: [YNABSubtransaction] = []) {
        self.id = id; self.date = date; self.amount = amount; self.memo = memo; self.cleared = cleared; self.approved = approved; self.accountId = accountId
        self.payeeId = payeeId; self.categoryId = categoryId; self.transferAccountId = transferAccountId; self.transferTransactionId = transferTransactionId
        self.importPayeeName = importPayeeName; self.deleted = deleted; self.subtransactions = subtransactions
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); date = try c.decode(String.self, forKey: .date); amount = try c.decode(Int64.self, forKey: .amount)
        memo = try c.decodeIfPresent(String.self, forKey: .memo); cleared = try c.decodeIfPresent(String.self, forKey: .cleared) ?? "uncleared"
        approved = try c.decodeIfPresent(Bool.self, forKey: .approved) ?? true; accountId = try c.decode(String.self, forKey: .accountId)
        payeeId = try c.decodeIfPresent(String.self, forKey: .payeeId); categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        transferAccountId = try c.decodeIfPresent(String.self, forKey: .transferAccountId); transferTransactionId = try c.decodeIfPresent(String.self, forKey: .transferTransactionId)
        importPayeeName = try c.decodeIfPresent(String.self, forKey: .importPayeeName)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        subtransactions = try c.decodeIfPresent([YNABSubtransaction].self, forKey: .subtransactions) ?? []
    }
    private enum Keys: String, CodingKey { case id, date, amount, memo, cleared, approved, accountId, payeeId, categoryId, transferAccountId, transferTransactionId, importPayeeName, deleted, subtransactions }
}

public struct YNABSnapshot: Sendable, Equatable {
    public var accounts: [YNABAccount]
    public var payees: [YNABPayee]
    public var groups: [YNABGroup]
    public var months: [YNABMonth]
    public var transactions: [YNABTransaction]

    public init(accounts: [YNABAccount] = [], payees: [YNABPayee] = [], groups: [YNABGroup] = [], months: [YNABMonth] = [], transactions: [YNABTransaction] = []) {
        self.accounts = accounts; self.payees = payees; self.groups = groups; self.months = months; self.transactions = transactions
    }
}
