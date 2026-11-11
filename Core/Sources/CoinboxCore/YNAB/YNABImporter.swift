import Foundation
import GRDB

extension Coinbox {
    /// The ops that bring the database to `desired`: only entities that differ, parents before children, plus deletes for
    /// imported transactions and assignments YNAB no longer has. Planning writes nothing.
    public func planYNABImport(_ d: YNABDesired) throws -> [Op] {
        var ops: [Op] = []
        func diff<T: Equatable>(_ wanted: [T], key: (T) -> String, existing: (String) throws -> T?, put: (T) -> Op) throws {
            for w in wanted where try existing(key(w)) != w { ops.append(put(w)) }
        }
        try diff(d.accounts, key: \.id, existing: { try account(id: $0) }, put: Op.putAccount)
        try diff(d.groups, key: \.id, existing: { try categoryGroup(id: $0) }, put: Op.putCategoryGroup)
        try diff(d.categories, key: \.id, existing: { try category(id: $0) }, put: Op.putCategory)
        try diff(d.payees, key: \.id, existing: { try payee(id: $0) }, put: Op.putPayee)
        try diff(d.targets, key: \.categoryID, existing: { try target(categoryID: $0) }, put: Op.putTarget)
        let have = Dictionary(try assignments().map { ("\($0.categoryID)|\($0.month)", $0) }, uniquingKeysWith: { a, _ in a })
        let wantedKeys = Set(d.assignments.map { "\($0.categoryID)|\($0.month)" })
        for a in d.assignments where have["\(a.categoryID)|\(a.month)"] != a { ops.append(.putAssignment(a)) }
        let months = Set(d.assignments.map(\.month))
        for (k, a) in have where months.contains(a.month) && !wantedKeys.contains(k) && a.categoryID.hasPrefix("ynab-") { ops.append(.deleteAssignment(categoryID: a.categoryID, month: a.month)) }
        for n in d.monthNotes where try monthNote(n.month) != n { ops.append(.putMonthNote(n)) }
        let existingTx = Dictionary(try transactions().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let wantedTx = Set(d.transactions.map(\.id))
        for t in d.transactions where existingTx[t.id] != t { ops.append(.putTransaction(t)) }
        for id in existingTx.keys.sorted() where id.hasPrefix("ynab-") && !wantedTx.contains(id) { ops.append(.deleteTransaction(id: id)) }
        return ops
    }

    /// Applies planned ops as `import`, in chunks so one change doesn't carry thousands of ops.
    public func applyYNABImport(_ ops: [Op], chunk: Int = 200) throws {
        var i = 0
        while i < ops.count {
            try perform(Array(ops[i..<min(i + chunk, ops.count)]), author: .importer)
            i += chunk
        }
    }
}

public enum YNABImporter {
    public static func currentDate() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    /// The month Ready to Assign is compared in: this month if YNAB has it, else the latest month it has. (YNAB shows a past month's Ready to Assign
    /// without the money assigned in later months, while this month's and later ones' subtract it, as Coinbox does for every month.)
    static func referenceMonth(_ snapshot: YNABSnapshot, today: String) -> MonthKey? {
        let months = snapshot.months.compactMap(\.key).sorted()
        let current = MonthKey.containing(date: today)
        return months.first { $0 == current } ?? months.last { $0 <= (current ?? $0) } ?? months.first
    }

    /// Replays `desired` in a scratch database and compares Ready to Assign in the reference month with YNAB's. States the difference in
    /// the report; with `options.plugOpeningRTA` and a positive gap, adds one inflow to close it.
    public static func finalize(_ d: inout YNABDesired, snapshot: YNABSnapshot, since: String, options: YNABOptions, today: String = currentDate()) throws {
        guard let first = referenceMonth(snapshot, today: today), let ynabRTA = snapshot.months.first(where: { $0.key == first })?.toBeBudgeted else { return }
        let scratch = try Coinbox.inMemory()
        try scratch.applyYNABImport(try scratch.planYNABImport(d))
        let ours = try scratch.budget(for: first).readyToAssign
        let gap = ynabRTA - ours
        guard gap != 0 else { return }
        d.report.warnings.append("Ready to Assign for \(first) is \(Money.format(ours)) here and \(Money.format(ynabRTA)) in YNAB (difference \(Money.format(gap)))")
        guard options.plugOpeningRTA else { return }
        guard gap > 0, let host = d.accounts.first(where: { $0.onBudget && $0.kind != .creditCard }) else {
            d.report.warnings.append("the difference can't be closed with an inflow; left as is")
            return
        }
        d.transactions.append(Transaction(id: "ynab-opening-rta-plug", accountID: host.id, date: MonthKey.dayBefore(since), memo: "Opening balance adjustment",
                                          amount: gap, cleared: .reconciled, approved: true, author: .importer, splits: []))
        d.transactions[d.transactions.count - 1].categoryID = Category.readyToAssignID
        d.report.counts["transactions", default: 0] += 1
    }
}
