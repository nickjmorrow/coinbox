import Foundation

/// The budget math, as pure functions over `BudgetInput`. Activity and Available are never stored: every call replays the
/// months from the first one with data. See the spec's "Budget math" section and the stage 2 plan's decisions.
public struct BudgetCalculator: Sendable {
    private let categories: [String: Category]
    private let accountKinds: [String: AccountKind]
    private let paymentCategory: [String: String]          // card account id → its payment category id
    private let targets: [String: Target]
    private let assignmentsByMonth: [MonthKey: [String: Milliunits]]
    private let linesByMonth: [MonthKey: [BudgetLine]]
    private let allLines: [BudgetLine]
    private let totalAssigned: Milliunits
    private let earliest: MonthKey?

    public init(_ input: BudgetInput) {
        categories = Dictionary(input.categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        accountKinds = Dictionary(input.accounts.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        var payments: [String: String] = [:]
        for c in input.categories { if case let .cardPayment(accountID) = c.kind { payments[accountID] = c.id } }
        paymentCategory = payments
        targets = Dictionary(input.targets.map { ($0.categoryID, $0) }, uniquingKeysWith: { a, _ in a })
        var byMonth: [MonthKey: [String: Milliunits]] = [:]
        var months: [MonthKey] = []
        for a in input.assignments {
            guard let m = MonthKey(a.month) else { continue }
            byMonth[m, default: [:]][a.categoryID, default: 0] += a.amount
            months.append(m)
        }
        assignmentsByMonth = byMonth
        totalAssigned = input.assignments.reduce(0) { $0 + $1.amount }
        var lineBuckets: [MonthKey: [BudgetLine]] = [:]
        for l in input.lines {
            guard let m = MonthKey.containing(date: l.date) else { continue }
            lineBuckets[m, default: []].append(l)
            months.append(m)
        }
        for m in lineBuckets.keys {
            // Same-day lines: larger amounts count as earlier (that is how YNAB orders card charges, which decides which card an overspent category's
            // credit part lands on), then by id so the order is the same on every device.
            lineBuckets[m]!.sort { ($0.date, -abs($0.amount), $0.transactionID, $0.lineIndex) < ($1.date, -abs($1.amount), $1.transactionID, $1.lineIndex) }
        }
        linesByMonth = lineBuckets
        allLines = input.lines
        earliest = months.min()
    }

    /// The key of the pseudo-category that holds spending nobody has categorized yet.
    public static let uncategorizedID = "uncategorized"

    private static func pos(_ x: Milliunits) -> Milliunits { max(0, x) }

    private func isBudgetable(_ c: Category) -> Bool {
        switch c.kind { case .normal, .cardPayment: return true; case .readyToAssign, .cardInterest: return false }
    }

    private struct Step {
        var months: [String: CategoryMonth]
        var nextCarry: [String: Milliunits]
        var cashOverspent: Milliunits
    }

    private func step(_ month: MonthKey, carry: [String: Milliunits]) -> Step {
        var available: [String: Milliunits] = [:]
        var result: [String: CategoryMonth] = [:]
        var cardNet: [String: [String: Milliunits]] = [:]       // category → card account → net card amount this month
        var cardLines: [String: [(account: String, amount: Milliunits)]] = [:]   // in the month's order
        var refundBack: [String: [String: Milliunits]] = [:]    // category → card account → refund that went back out of the payment category
        var uncategorized: Milliunits = 0, uncategorizedOnCards: Milliunits = 0
        let assigned = assignmentsByMonth[month] ?? [:]
        for c in categories.values where isBudgetable(c) {
            var cm = CategoryMonth()
            cm.carryover = carry[c.id] ?? 0
            cm.assigned = assigned[c.id] ?? 0
            result[c.id] = cm
            available[c.id] = cm.carryover + cm.assigned
        }
        for c in categories.values where c.kind == .cardInterest { result[c.id] = CategoryMonth() }

        for l in linesByMonth[month] ?? [] {
            guard let id = l.categoryID, let cat = categories[id] else {
                // A positive transfer leg into a card is a payment: outflow on its payment category.
                if l.isTransfer, l.amount > 0, accountKinds[l.accountID] == .creditCard, let p = paymentCategory[l.accountID], available[p] != nil {
                    result[p]!.activity -= l.amount
                    available[p]! -= l.amount
                } else if !l.isTransfer {
                    // Spending nobody has categorized yet: YNAB keeps it in an "Uncategorized" category, which counts as overspending.
                    uncategorized += l.amount
                    if accountKinds[l.accountID] == .creditCard { uncategorizedOnCards += l.amount }
                }
                continue
            }
            switch cat.kind {
            case .readyToAssign: continue
            case .cardInterest: result[id]!.activity += l.amount
            case .normal, .cardPayment:
                guard let before = available[id] else { continue }
                available[id]! += l.amount
                result[id]!.activity += l.amount
                if accountKinds[l.accountID] == .creditCard {
                    cardNet[id, default: [:]][l.accountID, default: 0] += l.amount
                    cardLines[id, default: []].append((l.accountID, l.amount))
                    // A refund first heals overspending; only what lifts the category above zero comes back out of the card's payment category.
                    if l.amount > 0 { refundBack[id, default: [:]][l.accountID, default: 0] += Self.pos(available[id]!) - Self.pos(before) }
                }
            }
        }

        // Spending on a card that a category's money covered moves to that card's payment category; a refund moves back. Worked out from
        // the month's totals, so the order of transactions within the month doesn't matter: moved = card spending − credit overspending.
        var credit: [String: Milliunits] = [:]
        let paymentIDs = Set(paymentCategory.values)
        for id in available.keys.sorted() where !paymentIDs.contains(id) {
            let a = available[id]!
            let lines = cardLines[id] ?? []
            let gross = lines.filter { $0.amount < 0 }.reduce(0) { $0 - $1.amount }
            let net = -(cardNet[id]?.values.reduce(0, +) ?? 0)
            let backTotal = refundBack[id]?.values.reduce(0, +) ?? 0
            let creditTotal = a < 0 ? min(-a, max(0, net)) : 0
            credit[id] = creditTotal
            // What the category's money covered: net card spending less the credit overspending, plus what refunds took back out.
            let covered = net - creditTotal + backTotal
            // The overspending sits on the latest card charges, so it is taken from the newest ones first.
            var creditByAccount: [String: Milliunits] = [:]
            var creditLeft = max(0, min(gross, gross - covered))
            for line in lines.reversed() where line.amount < 0 && creditLeft > 0 {
                let part = min(creditLeft, -line.amount)
                creditByAccount[line.account, default: 0] += part
                creditLeft -= part
            }
            for account in Set(lines.map(\.account)) {
                let spent = lines.filter { $0.account == account && $0.amount < 0 }.reduce(0) { $0 - $1.amount }
                let moved = spent - (creditByAccount[account] ?? 0) - (refundBack[id]?[account] ?? 0)
                if let p = paymentCategory[account], available[p] != nil {
                    result[p]!.activity += moved
                    available[p]! += moved
                }
            }
        }
        for id in paymentIDs where available[id] != nil { credit[id] = available[id]! < 0 ? min(-available[id]!, max(0, -(cardNet[id]?.values.reduce(0, +) ?? 0))) : 0 }

        var next: [String: Milliunits] = [:]
        var cash: Milliunits = 0
        if uncategorized != 0 {
            var u = CategoryMonth()
            u.activity = uncategorized
            if uncategorized < 0 {
                let shortfall = -uncategorized
                u.available = uncategorized
                u.creditOverspent = min(shortfall, max(0, -uncategorizedOnCards))
                u.cashOverspent = shortfall - u.creditOverspent
                cash += u.cashOverspent
            }
            result[Self.uncategorizedID] = u
        }
        for (id, a) in available {
            result[id]!.available = a
            if a < 0 {
                let shortfall = -a
                let c = credit[id] ?? 0
                result[id]!.creditOverspent = c
                result[id]!.cashOverspent = shortfall - c
                cash += shortfall - c
            } else if a > 0 {
                next[id] = a
            }
        }
        return Step(months: result, nextCarry: next, cashOverspent: cash)
    }

    private func underfunded(_ id: String, _ cm: CategoryMonth, month: MonthKey) -> Milliunits {
        if let cat = categories[id], case let .cardPayment(accountID) = cat.kind {
            let end = month.lastDay
            let balance = allLines.reduce(Milliunits(0)) { $0 + ($1.accountID == accountID && $1.date <= end ? $1.amount : 0) }
            return max(0, -balance - cm.available)
        }
        guard let t = targets[id] else { return 0 }
        return max(0, TargetMath.needed(t, in: month, carryover: cm.carryover) - cm.assigned)
    }

    public func summary(for month: MonthKey) -> MonthSummary {
        var carry: [String: Milliunits] = [:]
        var priorCash: Milliunits = 0
        var current: Step?
        for m in (min(earliest ?? month, month)).monthsThrough(month) {
            let s = step(m, carry: carry)
            if m < month { priorCash += s.cashOverspent }
            carry = s.nextCarry
            current = s
        }
        guard var s = current else { return MonthSummary(month: month, readyToAssign: 0, categories: [:], cashOverspending: 0) }
        let end = month.lastDay
        // Money put into a credit card account (a rewards credit, say) lowers the card's balance; YNAB doesn't count it as income to assign.
        let inflows = allLines.reduce(Milliunits(0)) { $0 + ($1.categoryID == Category.readyToAssignID && $1.date <= end && accountKinds[$1.accountID] != .creditCard ? $1.amount : 0) }
        for id in s.months.keys { s.months[id]!.underfunded = underfunded(id, s.months[id]!, month: month) }
        return MonthSummary(month: month, readyToAssign: inflows - totalAssigned - priorCash, categories: s.months, cashOverspending: s.cashOverspent)
    }
}
