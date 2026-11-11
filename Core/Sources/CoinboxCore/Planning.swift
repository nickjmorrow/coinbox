import Foundation
import GRDB

public struct AutoAssignResult: Sendable, Equatable {
    public var ops: [Op]
    public var assigned: Milliunits
    public var readyToAssignLeft: Milliunits
}

public struct Runway: Codable, Sendable, Equatable {
    public var cash: Milliunits
    public var costToBeMe: Milliunits
    /// Months of cost the cash covers, one decimal; nil when there is no cost yet.
    public var months: Double?

    public init(cash: Milliunits, costToBeMe: Milliunits, months: Double?) { self.cash = cash; self.costToBeMe = costToBeMe; self.months = months }
}

public struct MoneyMove: Codable, Sendable, Equatable {
    public struct Line: Codable, Sendable, Equatable, Hashable { public var categoryID: String; public var delta: Milliunits }
    public var changeID: Int64
    public var createdAt: Int64
    public var author: Author
    public var month: String
    public var lines: [Line]
    public var undone: Bool
}

public struct TransactionFilter: Sendable {
    public var accountID: String?
    public var categoryID: String?
    public var text: String?
    public var approved: Bool?
    public var from: String?
    public var to: String?
    public var uncategorized = false
    public init(accountID: String? = nil, categoryID: String? = nil, text: String? = nil, approved: Bool? = nil, from: String? = nil, to: String? = nil, uncategorized: Bool = false) {
        self.accountID = accountID; self.categoryID = categoryID; self.text = text; self.approved = approved; self.from = from; self.to = to; self.uncategorized = uncategorized
    }
}

extension Coinbox {
    /// Assigns each underfunded category what it needs, in plan order, until Ready to Assign runs out. Plans only.
    public func autoAssignOps(month: MonthKey) throws -> AutoAssignResult {
        let summary = try budget(for: month)
        var left = max(0, summary.readyToAssign)
        let groups = try categoryGroups().filter { !$0.hidden }
        let cats = try categories().filter { !$0.hidden }
        var ops: [Op] = [], total: Milliunits = 0
        for g in groups {
            for c in cats where c.groupID == g.id {
                guard left > 0, let m = summary.categories[c.id], m.underfunded > 0 else { continue }
                let give = min(m.underfunded, left)
                ops.append(.putAssignment(Assignment(categoryID: c.id, month: month.string, amount: m.assigned + give)))
                left -= give; total += give
            }
        }
        return AutoAssignResult(ops: ops, assigned: total, readyToAssignLeft: left)
    }

    /// Cash in on-budget checking, savings and cash accounts, against what the targets say a month costs.
    public func runway(asOf month: MonthKey) throws -> Runway {
        let kinds: Set<AccountKind> = [.checking, .savings, .cash]
        let balances = try accountBalances()
        let cash = try accounts().filter { $0.onBudget && !$0.closed && kinds.contains($0.kind) }.reduce(Milliunits(0)) { $0 + (balances[$1.id]?.total ?? 0) }
        let cost = TargetMath.costToBeMe(try targets(), asOf: month)
        return Runway(cash: cash, costToBeMe: cost, months: cost > 0 ? (Double(cash) / Double(cost) * 10).rounded() / 10 : nil)
    }

    /// Assignment changes in `month`, newest first, read from the change log (each with how much each category moved).
    public func moneyMoves(month: String) throws -> [MoneyMove] {
        try db.read { db in
            var out: [MoneyMove] = []
            let decoder = JSONDecoder()
            for row in try Row.fetchAll(db, sql: "SELECT local_id, author, payload, inverse, created_at, undone_by, undoes FROM ops WHERE kind IN ('putAssignment', 'deleteAssignment', 'batch') AND undoes IS NULL ORDER BY local_id DESC") {
                guard let op = try? decoder.decode(Op.self, from: Data((row["payload"] as String).utf8)) else { continue }
                var previous: [String: Milliunits] = [:]
                if let inv: String = row["inverse"], let invOp = try? decoder.decode(Op.self, from: Data(inv.utf8)) {
                    for leaf in invOp.leaves { if case let .putAssignment(a) = leaf { previous["\(a.categoryID)|\(a.month)"] = a.amount } }
                }
                var lines: [MoneyMove.Line] = []
                for leaf in op.leaves {
                    switch leaf {
                    case let .putAssignment(a) where a.month == month:
                        lines.append(.init(categoryID: a.categoryID, delta: a.amount - (previous["\(a.categoryID)|\(a.month)"] ?? 0)))
                    case let .deleteAssignment(cat, m) where m == month:
                        lines.append(.init(categoryID: cat, delta: -(previous["\(cat)|\(m)"] ?? 0)))
                    default: break
                    }
                }
                guard !lines.isEmpty else { continue }
                out.append(MoneyMove(changeID: row["local_id"], createdAt: row["created_at"], author: Author(rawValue: row["author"]) ?? .importer, month: month, lines: lines,
                                     undone: (row["undone_by"] as Int64?) != nil))
            }
            return out
        }
    }

    /// Transactions matching every part of the filter, newest first.
    public func search(_ f: TransactionFilter) throws -> [Transaction] {
        let payees = Dictionary(try self.payees().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let cats = Dictionary(try categories().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let needle = f.text?.trimmingCharacters(in: .whitespaces).lowercased().nilIfEmpty
        return try transactions(accountID: f.accountID).filter { t in
            if let c = f.categoryID, t.categoryID != c, !t.splits.contains(where: { $0.categoryID == c }) { return false }
            if let a = f.approved, t.approved != a { return false }
            if let from = f.from, t.date < from { return false }
            if let to = f.to, t.date > to { return false }
            if f.uncategorized, !(t.categoryID == nil && t.splits.isEmpty && t.transferPairID == nil) { return false }
            if let n = needle {
                let haystack = [payees[t.payeeID ?? ""], t.rawPayee, t.memo, cats[t.categoryID ?? ""], Money.format(t.amount), t.date].compactMap { $0 }.joined(separator: " ").lowercased()
                if !haystack.contains(n) { return false }
            }
            return true
        }.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
