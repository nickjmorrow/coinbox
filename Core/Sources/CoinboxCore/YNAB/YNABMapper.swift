import Foundation

public struct YNABOptions: Sendable {
    /// The YNAB category to treat as card interest (never overspent, never assigned). Nil by default: in a typical plan Interest & Fees is
    /// funded like any other category, and importing it as a normal one is what reproduces YNAB's numbers.
    public var interestCategoryName: String?
    public var plugOpeningRTA = false
    public init(interestCategoryName: String? = nil, plugOpeningRTA: Bool = false) {
        self.interestCategoryName = interestCategoryName; self.plugOpeningRTA = plugOpeningRTA
    }
}

public struct YNABReport: Codable, Sendable, Equatable {
    public var counts: [String: Int] = [:]
    public var warnings: [String] = []
    public init() {}
}

/// What the database should hold after the import.
public struct YNABDesired: Sendable {
    public var accounts: [Account] = []
    public var groups: [CategoryGroup] = []
    public var categories: [Category] = []
    public var payees: [Payee] = []
    public var assignments: [Assignment] = []
    public var targets: [Target] = []
    public var transactions: [Transaction] = []
    public var monthNotes: [MonthNote] = []
    public var report = YNABReport()
}

public enum YNABMapper {
    static let internalGroup = "Internal Master Category"
    static let cardGroup = "Credit Card Payments"

    static func id(_ ynab: String) -> String { "ynab-" + ynab }

    static func kind(of a: YNABAccount) -> AccountKind {
        switch a.type {
        case "checking": return .checking
        case "savings": return .savings
        case "cash": return .cash
        case "creditCard": return .creditCard
        case "lineOfCredit": return a.onBudget ? .creditCard : .loan
        case "mortgage": return .mortgage
        case "otherAsset": return .asset
        default: return .loan      // autoLoan, studentLoan, personalLoan, medicalDebt, otherDebt, otherLiability
        }
    }

    static func target(for c: YNABCategory) -> (Target?, String?) {
        guard let type = c.goalType, let amount = c.goalTarget, amount > 0 else { return (nil, nil) }
        let cat = id(c.id)
        func unmapped(_ why: String) -> (Target?, String?) { (nil, "goal on “\(c.name)” not imported: \(why)") }
        let due = c.goalTargetDate
        switch type {
        case "MF": return (Target(categoryID: cat, cadence: .monthly(day: c.goalDay ?? 31), amount: amount), nil)
        case "TBD":
            guard let due else { return unmapped("target by date has no date") }
            return (Target(categoryID: cat, cadence: .byDate(due), amount: amount), nil)
        case "NEED":
            let cadence = c.goalCadence ?? 1, freq = max(1, c.goalCadenceFrequency ?? 1)
            switch cadence {
            case 1:
                if freq == 1 { return (Target(categoryID: cat, cadence: .monthly(day: c.goalDay ?? 31), amount: amount), nil) }
                guard let due else { return unmapped("repeats every \(freq) months without a due date") }
                return (Target(categoryID: cat, cadence: .everyMonths(n: freq, firstDue: due), amount: amount), nil)
            case 2:
                let day = c.goalDay ?? 1
                return (Target(categoryID: cat, cadence: .weekly(isoWeekday: day == 0 ? 7 : day), amount: amount), nil)
            case 13:
                guard let due, due.count == 10, let m = Int(due.dropFirst(5).prefix(2)), let d = Int(due.suffix(2)) else { return unmapped("yearly without a due date") }
                if freq == 1 { return (Target(categoryID: cat, cadence: .yearly(month: m, day: d), amount: amount), nil) }
                return (Target(categoryID: cat, cadence: .everyMonths(n: 12 * freq, firstDue: due), amount: amount), nil)
            case 3...12, 14:
                guard let due else { return unmapped("repeating goal without a due date") }
                return (Target(categoryID: cat, cadence: .everyMonths(n: cadence == 14 ? 24 : cadence - 1, firstDue: due), amount: amount), nil)
            default:
                guard let due else { return unmapped("one-time goal without a date") }
                return (Target(categoryID: cat, cadence: .byDate(due), amount: amount), nil)
            }
        default: return unmapped("goal type \(type) isn't supported yet")
        }
    }

    public static func map(_ s: YNABSnapshot, since: String, options: YNABOptions = YNABOptions()) -> YNABDesired {
        var out = YNABDesired()
        var warnings: [String] = []

        // Accounts
        let liveAccounts = s.accounts.filter { !$0.deleted }
        var accountByYNAB: [String: Account] = [:]
        for a in liveAccounts {
            let acct = Account(id: id(a.id), name: a.name, kind: kind(of: a), onBudget: a.onBudget, closed: a.closed, note: a.note, ynabID: a.id)
            out.accounts.append(acct); accountByYNAB[a.id] = acct
        }
        let cardsByName = Dictionary(out.accounts.filter { $0.kind == .creditCard }.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        // Groups and categories
        var categoryMap: [String: String?] = [:]            // YNAB category id → our id (nil: deliberately uncategorized)
        var paymentYNABIDs: [String: String] = [:]          // our payment category id → YNAB category id
        var groupOrder = 0
        for g in s.groups where !g.deleted {
            if g.name == internalGroup {
                for c in g.categories {
                    categoryMap[c.id] = c.name.hasPrefix("Inflow") ? Category.readyToAssignID : .some(nil)
                    if c.name.hasPrefix("Inflow") { out.categories.append(Category(id: Category.readyToAssignID, groupID: CategoryGroup.inflowID, name: "Ready to Assign", order: 0, kind: .readyToAssign, ynabID: c.id)) }
                }
                continue
            }
            if g.name == cardGroup {
                for c in g.categories where !c.deleted {
                    if let card = cardsByName[c.name] { categoryMap[c.id] = "card-payment-\(card.id)"; paymentYNABIDs["card-payment-\(card.id)"] = c.id }
                    else { categoryMap[c.id] = .some(nil); warnings.append("credit card payment category “\(c.name)” has no matching credit card account; its transactions are left uncategorized") }
                }
                continue
            }
            let gid = id(g.id)
            out.groups.append(CategoryGroup(id: gid, name: g.name, order: groupOrder, hidden: g.hidden)); groupOrder += 1
            for (i, c) in g.categories.enumerated() where !c.deleted {
                if let interest = options.interestCategoryName, c.name == interest {
                    categoryMap[c.id] = Category.cardInterestID
                    out.categories.append(Category(id: Category.cardInterestID, groupID: CategoryGroup.cardPaymentsID, name: "Interest & Fees", order: 1000, hidden: c.hidden, note: c.note, kind: .cardInterest, ynabID: c.id))
                    continue
                }
                categoryMap[c.id] = id(c.id)
                out.categories.append(Category(id: id(c.id), groupID: gid, name: c.name, order: i, hidden: c.hidden, note: c.note, kind: .normal, ynabID: c.id))
                let (t, why) = target(for: c)
                if let t { out.targets.append(t) } else if let why { warnings.append(why) }
            }
        }
        for card in out.accounts where card.kind == .creditCard {
            let pid = "card-payment-\(card.id)"
            out.categories.append(Category(id: pid, groupID: CategoryGroup.cardPaymentsID, name: card.name, kind: .cardPayment(accountID: card.id), ynabID: paymentYNABIDs[pid]))
        }

        // Payees
        let livePayees = Set(s.payees.filter { !$0.deleted }.map(\.id))
        let payeeNames = Dictionary(s.payees.filter { !$0.deleted }.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for p in s.payees where !p.deleted {
            out.payees.append(Payee(id: id(p.id), name: p.name, transferAccountID: p.transferAccountId.flatMap { accountByYNAB[$0]?.id }))
        }

        // Transactions
        func mapped(_ ynab: String?) -> (id: String?, known: Bool) {
            guard let ynab else { return (nil, true) }
            guard let v = categoryMap[ynab] else { return (nil, false) }
            return (v, true)
        }
        var sumByAccount: [String: Int64] = [:]
        for t in s.transactions where !t.deleted && t.date >= since {
            guard let account = accountByYNAB[t.accountId] else { continue }
            var splits: [SplitLine] = []
            var categoryID: String? = nil
            let subs = t.subtransactions.filter { !$0.deleted }
            func fix(_ c: String?, _ amount: Int64) -> String? {
                if c == Category.readyToAssignID && amount < 0 { warnings.append("\(t.date) \(Money.format(amount)) in \(account.name): outflow from Ready to Assign imported uncategorized"); return nil }
                return c
            }
            if subs.isEmpty {
                let m = mapped(t.categoryId)
                if !m.known { warnings.append("\(t.date) in \(account.name): unknown category, imported uncategorized") }
                categoryID = fix(m.id, t.amount)
            } else {
                let lines = subs.map { SplitLine(categoryID: fix(mapped($0.categoryId).id, $0.amount) ?? "", amount: $0.amount, memo: $0.memo) }
                if lines.count >= 2, lines.allSatisfy({ !$0.categoryID.isEmpty }), lines.reduce(0, { $0 + $1.amount }) == t.amount { splits = lines }
                else { warnings.append("\(t.date) \(Money.format(t.amount)) in \(account.name): split has an uncategorized or mismatched part, imported unsplit") }
            }
            let cleared = ClearedState(rawValue: t.cleared) ?? .uncleared
            out.transactions.append(Transaction(id: id(t.id), accountID: account.id, date: t.date, payeeID: t.payeeId.flatMap { livePayees.contains($0) ? id($0) : nil },
                                                categoryID: categoryID, memo: t.memo, amount: t.amount, cleared: cleared, approved: t.approved,
                                                transferPairID: t.transferTransactionId.map(id), ynabID: t.id,
                                                rawPayee: t.importPayeeName ?? t.payeeId.flatMap { payeeNames[$0] }, author: .importer, splits: splits))
            sumByAccount[account.id, default: 0] += t.amount
        }

        // Starting balances, the day before `since`
        let openDay = MonthKey.dayBefore(since)
        for a in liveAccounts {
            let acct = accountByYNAB[a.id]!
            let start = a.balance - (sumByAccount[acct.id] ?? 0)
            guard start != 0 else { continue }
            let toRTA = acct.onBudget && acct.kind != .creditCard && start > 0
            if acct.onBudget && !toRTA { warnings.append("starting balance of \(Money.format(start)) in \(acct.name) is not funded (imported uncategorized)") }
            out.transactions.append(Transaction(id: "ynab-start-\(a.id)", accountID: acct.id, date: openDay, memo: "Starting Balance", amount: start,
                                                cleared: .reconciled, approved: true, author: .importer))
            if toRTA { out.transactions[out.transactions.count - 1].categoryID = Category.readyToAssignID }
        }

        // Assignments, opening assignments, month notes
        let firstMonth = s.months.compactMap(\.key).min()
        for m in s.months {
            guard let key = m.key else { continue }
            for c in m.categories {
                guard let ours = categoryMap[c.id] ?? nil else { continue }
                if c.budgeted != 0 {
                    if ours == Category.readyToAssignID || ours == Category.cardInterestID { warnings.append("\(key): money assigned to a category that can't take it was skipped"); continue }
                    out.assignments.append(Assignment(categoryID: ours, month: key.string, amount: c.budgeted))
                }
                if key == firstMonth, ours != Category.readyToAssignID, ours != Category.cardInterestID {
                    let carry = c.balance - c.budgeted - c.activity
                    if carry > 0 { out.assignments.append(Assignment(categoryID: ours, month: key.previous.string, amount: carry)) }
                }
            }
            if let note = m.note, !note.isEmpty { out.monthNotes.append(MonthNote(month: key.string, text: note)) }
        }

        out.report.warnings = warnings
        out.report.counts = ["accounts": out.accounts.count, "groups": out.groups.count, "categories": out.categories.count, "payees": out.payees.count,
                             "assignments": out.assignments.count, "targets": out.targets.count, "transactions": out.transactions.count, "monthNotes": out.monthNotes.count]
        return out
    }
}
