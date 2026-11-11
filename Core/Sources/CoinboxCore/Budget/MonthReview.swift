import Foundation

/// Where one payee's money went in one category over the month.
public struct PayeeSpend: Codable, Sendable, Equatable {
    public var name: String
    public var spent: Milliunits
    public var count: Int
}

/// One category in a month review. `spent` is positive for money out (refunds net against it).
public struct CategoryReview: Codable, Sendable, Equatable {
    public var categoryID: String
    public var name: String
    public var groupID: String
    public var groupName: String
    public var spent: Milliunits
    public var assigned: Milliunits
    /// What the next month has assigned so far, and that plus what carries into it: the money set aside before any of its spending.
    public var nextAssigned: Milliunits
    public var nextFunded: Milliunits
    /// Average monthly spending over this month and the two before it.
    public var averageSpent: Milliunits
    public var transactionCount: Int
    public var topPayees: [PayeeSpend]

    /// Next month's money set aside for this category, less what this month spent. Negative means the plan is short of last month's pace.
    public var planGap: Milliunits { nextFunded - spent }
}

public struct GroupReview: Codable, Sendable, Equatable {
    public var groupID: String
    public var name: String
    public var spent: Milliunits
    public var nextAssigned: Milliunits
    public var categories: [CategoryReview]
}

/// How a month's money went, set against the next month's plan.
public struct MonthReview: Codable, Sendable, Equatable {
    public var month: String
    public var nextMonth: String
    /// Money in to Ready to Assign this month.
    public var income: Milliunits
    public var spent: Milliunits
    public var nextAssigned: Milliunits
    /// Groups by spending, largest first; each group's categories likewise. Categories with no spending and nothing planned are left out.
    public var groups: [GroupReview]
}

extension Coinbox {
    public func monthReview(_ month: MonthKey) throws -> MonthReview {
        let calc = try calculator()
        let this = calc.summary(for: month), next = calc.summary(for: month.next)
        let prior = [month.adding(months: -1), month.adding(months: -2)].map { calc.summary(for: $0) }
        let groups = Dictionary(try categoryGroups().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let payeeName = Dictionary(try payees().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let onBudget = Set(try accounts().filter(\.onBudget).map(\.id))

        // Payees per category from the month's lines (splits counted per line).
        var byCategory: [String: [String: (Milliunits, Int)]] = [:]
        var counts: [String: Int] = [:]
        var income: Milliunits = 0
        for t in try transactions() where onBudget.contains(t.accountID) && t.date.hasPrefix(month.string) && t.transferPairID == nil {
            let who = t.payeeID.flatMap { payeeName[$0] } ?? t.rawPayee ?? "No payee"
            let lines = t.splits.isEmpty ? [(t.categoryID, t.amount)] : t.splits.map { ($0.categoryID, $0.amount) }
            for (cat, amount) in lines {
                guard let cat else { continue }
                if cat == Category.readyToAssignID { income += amount; continue }
                var entry = byCategory[cat, default: [:]][who] ?? (0, 0)
                entry.0 -= amount; entry.1 += 1
                byCategory[cat, default: [:]][who] = entry
                counts[cat, default: 0] += 1
            }
        }

        var reviews: [CategoryReview] = []
        for c in try categories() where c.kind == .normal || c.kind == .cardInterest {
            let spent = -(this.categories[c.id]?.activity ?? 0)
            let nextAssigned = next.categories[c.id]?.assigned ?? 0
            guard spent != 0 || nextAssigned != 0 else { continue }
            let history = [spent] + prior.map { -($0.categories[c.id]?.activity ?? 0) }
            let top = (byCategory[c.id] ?? [:]).map { PayeeSpend(name: $0.key, spent: $0.value.0, count: $0.value.1) }
                .sorted { ($0.spent, $1.name) > ($1.spent, $0.name) }.prefix(5)
            reviews.append(CategoryReview(categoryID: c.id, name: c.name, groupID: c.groupID, groupName: groups[c.groupID]?.name ?? "",
                                          spent: spent, assigned: this.categories[c.id]?.assigned ?? 0, nextAssigned: nextAssigned,
                                          nextFunded: (next.categories[c.id]?.assigned ?? 0) + (next.categories[c.id]?.carryover ?? 0), averageSpent: Money.divideRounded(history.reduce(0, +), 3),
                                          transactionCount: counts[c.id] ?? 0, topPayees: Array(top)))
        }
        let grouped = Dictionary(grouping: reviews, by: \.groupID).map { id, cats in
            GroupReview(groupID: id, name: groups[id]?.name ?? "", spent: cats.reduce(0) { $0 + $1.spent }, nextAssigned: cats.reduce(0) { $0 + $1.nextAssigned },
                        categories: cats.sorted { ($0.spent, $1.name) > ($1.spent, $0.name) })
        }.sorted { ($0.spent, $1.name) > ($1.spent, $0.name) }
        return MonthReview(month: month.string, nextMonth: month.next.string, income: income, spent: grouped.reduce(0) { $0 + $1.spent },
                           nextAssigned: grouped.reduce(0) { $0 + $1.nextAssigned }, groups: grouped)
    }
}
