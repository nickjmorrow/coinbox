import Foundation

/// One category's slice of one transaction (a split parent contributes one line per split).
public struct BudgetLine: Sendable, Equatable {
    public var transactionID: String
    public var lineIndex: Int
    public var date: String
    public var accountID: String
    public var categoryID: String?
    public var amount: Milliunits
    public var isTransfer: Bool

    public init(transactionID: String, lineIndex: Int, date: String, accountID: String, categoryID: String?, amount: Milliunits, isTransfer: Bool) {
        self.transactionID = transactionID; self.lineIndex = lineIndex; self.date = date; self.accountID = accountID
        self.categoryID = categoryID; self.amount = amount; self.isTransfer = isTransfer
    }
}

public struct BudgetInput: Sendable {
    public var accounts: [Account]
    public var categories: [Category]
    public var assignments: [Assignment]
    public var targets: [Target]
    /// Lines from on-budget accounts only.
    public var lines: [BudgetLine]

    public init(accounts: [Account], categories: [Category], assignments: [Assignment], targets: [Target], lines: [BudgetLine]) {
        self.accounts = accounts; self.categories = categories; self.assignments = assignments; self.targets = targets; self.lines = lines
    }

    public static func make(accounts: [Account], categories: [Category], assignments: [Assignment], targets: [Target], transactions: [Transaction]) -> BudgetInput {
        let onBudget = Set(accounts.filter(\.onBudget).map(\.id))
        var lines: [BudgetLine] = []
        for t in transactions where onBudget.contains(t.accountID) {
            if t.splits.isEmpty {
                lines.append(BudgetLine(transactionID: t.id, lineIndex: 0, date: t.date, accountID: t.accountID, categoryID: t.categoryID, amount: t.amount, isTransfer: t.transferPairID != nil))
            } else {
                for (i, s) in t.splits.enumerated() {
                    lines.append(BudgetLine(transactionID: t.id, lineIndex: i, date: t.date, accountID: t.accountID, categoryID: s.categoryID, amount: s.amount, isTransfer: t.transferPairID != nil))
                }
            }
        }
        return BudgetInput(accounts: accounts, categories: categories, assignments: assignments, targets: targets, lines: lines)
    }
}

public struct CategoryMonth: Sendable, Equatable {
    public var assigned: Milliunits = 0
    public var activity: Milliunits = 0
    public var available: Milliunits = 0
    public var carryover: Milliunits = 0
    public var cashOverspent: Milliunits = 0
    public var creditOverspent: Milliunits = 0
    public var underfunded: Milliunits = 0

    public init() {}
}

public struct MonthSummary: Sendable, Equatable {
    public var month: MonthKey
    public var readyToAssign: Milliunits
    public var categories: [String: CategoryMonth]
    /// Cash overspent in this month, across categories; it comes out of the next month's Ready to Assign.
    public var cashOverspending: Milliunits

    public init(month: MonthKey, readyToAssign: Milliunits, categories: [String: CategoryMonth], cashOverspending: Milliunits) {
        self.month = month; self.readyToAssign = readyToAssign; self.categories = categories; self.cashOverspending = cashOverspending
    }
}
