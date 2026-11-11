import Foundation

/// One transaction's before and after in a planned batch. `skipped` says why a transaction was left alone.
public struct PlannedChange: Codable, Sendable, Equatable {
    public var transactionID: String
    public var date: String
    public var amount: Milliunits
    public var rawPayee: String?
    public var payeeBefore: String?
    public var payeeAfter: String?
    public var categoryBefore: String?
    public var categoryAfter: String?
    public var memoBefore: String?
    public var memoAfter: String?
    public var approvedBefore: Bool
    public var approvedAfter: Bool
    /// "rule <name>", "payee default", or "manual".
    public var source: String
    public var skipped: String?
}

public struct PlannedBatch: Codable, Sendable, Equatable {
    public var changes: [PlannedChange]
    public var ops: [Op]
}

/// Plans bulk edits against a snapshot of the database. Nothing is written until the caller performs `ops`.
final class BatchPlanner {
    let original: [String: Transaction]
    var edited: [String: Transaction] = [:]
    var editOrder: [String] = []
    var sources: [String: String] = [:]
    var skipped: [String: String] = [:]
    var payees: [String: Payee]
    let accounts: [String: Account]
    let categories: [String: Category]
    var payeeOps: [Op] = []
    var payeeByLowerName: [String: Payee] = [:]
    var allTransactions: [Transaction]

    init(_ c: Coinbox) throws {
        allTransactions = try c.transactions()
        original = Dictionary(allTransactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        payees = Dictionary(try c.payees().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        accounts = Dictionary(try c.accounts().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        categories = Dictionary(try c.categories().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for p in payees.values { payeeByLowerName[p.name.lowercased()] = p }
    }

    func current(_ id: String) -> Transaction? { edited[id] ?? original[id] }

    func record(_ t: Transaction, source: String) {
        if edited[t.id] == nil { editOrder.append(t.id); sources[t.id] = source }
        edited[t.id] = t
    }

    func skip(_ id: String, _ why: String) { if skipped[id] == nil { skipped[id] = why } }

    /// A payee with this name (any case), creating it once per batch.
    func payee(named name: String) -> Payee {
        if let p = payeeByLowerName[name.lowercased()] { return p }
        let p = Payee(id: "payee-" + UUID().uuidString.lowercased(), name: name)
        payeeByLowerName[name.lowercased()] = p
        payees[p.id] = p
        payeeOps.append(.putPayee(p))
        return p
    }

    /// Why this category can't take this amount, or nil.
    func categoryProblem(_ categoryID: String, amount: Milliunits) -> String? {
        guard let c = categories[categoryID] else { return "category \(categoryID) doesn't exist" }
        if c.kind == .readyToAssign && amount < 0 { return "an outflow can't be categorized to Ready to Assign" }
        return nil
    }

    func approve(_ id: String, source: String) {
        guard var t = current(id) else { skip(id, "not found"); return }
        if !t.approved { t.approved = true; record(t, source: source) }
        if let pair = t.transferPairID, var partner = current(pair), !partner.approved { partner.approved = true; record(partner, source: source) }
    }

    func categorize(_ id: String, to categoryID: String, source: String) {
        guard var t = current(id) else { skip(id, "not found"); return }
        guard t.splits.isEmpty else { skip(id, "it's a split; edit its lines instead"); return }
        if let pair = t.transferPairID, let partner = current(pair), accounts[t.accountID]?.onBudget == true, accounts[partner.accountID]?.onBudget == true {
            skip(id, "a transfer between on-budget accounts has no category"); return
        }
        if let why = categoryProblem(categoryID, amount: t.amount) { skip(id, why); return }
        if t.categoryID != categoryID { t.categoryID = categoryID; record(t, source: source) }
    }

    func finish() -> PlannedBatch {
        var changes: [PlannedChange] = []
        var ops = payeeOps
        func name(_ id: String?) -> String? { id.flatMap { payees[$0]?.name } }
        for id in editOrder {
            let before = original[id]!, after = edited[id]!
            changes.append(PlannedChange(transactionID: id, date: after.date, amount: after.amount, rawPayee: after.rawPayee,
                                         payeeBefore: name(before.payeeID), payeeAfter: name(after.payeeID), categoryBefore: before.categoryID,
                                         categoryAfter: after.categoryID, memoBefore: before.memo, memoAfter: after.memo, approvedBefore: before.approved,
                                         approvedAfter: after.approved, source: sources[id] ?? "manual", skipped: nil))
            ops.append(.putTransaction(after))
        }
        for (id, why) in skipped.sorted(by: { $0.key < $1.key }) where edited[id] == nil {
            let t = original[id]
            changes.append(PlannedChange(transactionID: id, date: t?.date ?? "", amount: t?.amount ?? 0, rawPayee: t?.rawPayee, payeeBefore: name(t?.payeeID), payeeAfter: name(t?.payeeID),
                                         categoryBefore: t?.categoryID, categoryAfter: t?.categoryID, memoBefore: t?.memo, memoAfter: t?.memo,
                                         approvedBefore: t?.approved ?? false, approvedAfter: t?.approved ?? false, source: "manual", skipped: why))
        }
        // Payee defaults follow what was just approved or categorized.
        var merged = allTransactions.map { edited[$0.id] ?? $0 }
        merged.append(contentsOf: edited.values.filter { original[$0.id] == nil })
        for pid in Set(edited.values.compactMap(\.payeeID)).sorted() {
            guard var p = payees[pid], let learned = PayeeLearning.learnedDefault(of: p, in: merged) else { continue }
            p.defaultCategoryID = learned
            ops.append(.putPayee(p))
        }
        return PlannedBatch(changes: changes, ops: ops)
    }
}

enum PayeeLearning {
    /// The payee's new default category: when two of its last three approved, categorized, unsplit transactions agree, and the
    /// default isn't locked and doesn't already match. Nil means leave it.
    static func learnedDefault(of payee: Payee, in transactions: [Transaction]) -> String? {
        guard !payee.defaultLocked else { return nil }
        let recent = transactions.filter { $0.payeeID == payee.id && $0.approved && $0.categoryID != nil && $0.splits.isEmpty }
            .sorted { ($0.date, $0.id) > ($1.date, $1.id) }.prefix(3)
        var counts: [String: Int] = [:]
        for t in recent { counts[t.categoryID!, default: 0] += 1 }
        guard let best = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), best.value >= 2, best.key != payee.defaultCategoryID else { return nil }
        return best.key
    }
}

extension Coinbox {
    /// The category this payee's default should become given its history, or nil to leave it.
    public func learnedDefault(payeeID: String) throws -> String? {
        guard let p = try payee(id: payeeID) else { throw CoinboxError.notFound("payee \(payeeID)") }
        return PayeeLearning.learnedDefault(of: p, in: try transactions())
    }

    public func planApprove(ids: [String]) throws -> PlannedBatch {
        let b = try BatchPlanner(self)
        for id in ids { b.approve(id, source: "manual") }
        return b.finish()
    }

    public func planCategorize(ids: [String], categoryID: String, approve: Bool = false) throws -> PlannedBatch {
        let b = try BatchPlanner(self)
        for id in ids { b.categorize(id, to: categoryID, source: "manual"); if approve, b.skipped[id] == nil { b.approve(id, source: "manual") } }
        return b.finish()
    }

    /// Deleting a transfer leg deletes its partner too.
    public func planDelete(ids: [String]) throws -> PlannedBatch {
        let all = Dictionary(try transactions().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order: [String] = []
        var changes: [PlannedChange] = []
        for id in ids {
            guard let t = all[id] else {
                changes.append(PlannedChange(transactionID: id, date: "", amount: 0, rawPayee: nil, payeeBefore: nil, payeeAfter: nil, categoryBefore: nil, categoryAfter: nil,
                                             memoBefore: nil, memoAfter: nil, approvedBefore: false, approvedAfter: false, source: "manual", skipped: "not found"))
                continue
            }
            for victim in [t] + (t.transferPairID.flatMap { all[$0] }.map { [$0] } ?? []) where !order.contains(victim.id) {
                order.append(victim.id)
                changes.append(PlannedChange(transactionID: victim.id, date: victim.date, amount: victim.amount, rawPayee: victim.rawPayee, payeeBefore: nil, payeeAfter: nil,
                                             categoryBefore: victim.categoryID, categoryAfter: nil, memoBefore: victim.memo, memoAfter: nil,
                                             approvedBefore: victim.approved, approvedAfter: victim.approved, source: "manual", skipped: nil))
            }
        }
        let linked = Set(try amazonLinks().map(\.transactionID))
        return PlannedBatch(changes: changes, ops: order.flatMap { id -> [Op] in linked.contains(id) ? [.deleteAmazonLink(transactionID: id), .deleteTransaction(id: id)] : [.deleteTransaction(id: id)] })
    }

    /// Rules that can never match because a regex in them doesn't compile.
    public func rulesWithBrokenRegex() throws -> [Rule] {
        try rules().filter { RuleEngine.isBrokenRegex($0.payee) || RuleEngine.isBrokenRegex($0.memo) }
    }

    /// Runs the rules over `ids` (default: every unapproved transaction). A transaction with no matching rule and no category gets its
    /// payee's default category (not approved). Plans only.
    public func planRuleApplication(ids: [String]? = nil) throws -> PlannedBatch {
        let b = try BatchPlanner(self)
        let rules = try self.rules()
        let targets = (ids ?? b.original.values.filter { !$0.approved }.sorted { ($0.date, $0.id) < ($1.date, $1.id) }.map(\.id))
        for id in targets {
            guard var t = b.current(id) else { b.skip(id, "not found"); continue }
            guard t.splits.isEmpty else { b.skip(id, "it's a split; edit its lines instead"); continue }
            let payeeName = t.payeeID.flatMap { b.payees[$0]?.name }
            if let rule = RuleEngine.firstMatch(rules, for: t, payeeName: payeeName) {
                let a = rule.actions
                if let cat = a.categoryID, let why = b.categoryProblem(cat, amount: t.amount) { b.skip(id, "rule “\(rule.name)”: \(why)"); continue }
                if let name = a.renamePayee { t.payeeID = b.payee(named: name).id }
                if let cat = a.categoryID { t.categoryID = cat }
                if let memo = a.memo { t.memo = memo }
                if t != b.original[id] { b.record(t, source: "rule \(rule.name)") }
                if a.approve { b.approve(id, source: "rule \(rule.name)") }
            } else if t.categoryID == nil, let pid = t.payeeID, let def = b.payees[pid]?.defaultCategoryID, b.categoryProblem(def, amount: t.amount) == nil,
                      !(t.transferPairID != nil && b.accounts[t.accountID]?.onBudget == true) {
                t.categoryID = def
                b.record(t, source: "payee default")
            }
        }
        return b.finish()
    }
}
