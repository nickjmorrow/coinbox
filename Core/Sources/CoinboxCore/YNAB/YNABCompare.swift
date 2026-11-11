import Foundation

public struct YNABDifference: Codable, Sendable, Equatable {
    public var scope: String
    public var subject: String
    public var ynab: Milliunits
    public var coinbox: Milliunits
}

extension Coinbox {
    /// Every number that differs from what YNAB reports: Ready to Assign and each category's assigned/activity/available per month
    /// (months in the snapshot), and each account's balance.
    public func compareToYNAB(_ snapshot: YNABSnapshot, today: String = YNABImporter.currentDate()) throws -> [YNABDifference] {
        var out: [YNABDifference] = []
        let cats = try categories()
        let byYNAB = Dictionary(cats.compactMap { c in c.ynabID.map { ($0, c) } }, uniquingKeysWith: { a, _ in a })
        let calculator = try self.calculator()
        for m in snapshot.months {
            guard let key = m.key else { continue }
            let ours = calculator.summary(for: key)
            func check(_ subject: String, _ ynab: Milliunits, _ coinbox: Milliunits) {
                if ynab != coinbox { out.append(YNABDifference(scope: key.string, subject: subject, ynab: ynab, coinbox: coinbox)) }
            }
            // YNAB's Ready to Assign for a past month leaves out what was assigned in later months, so only this month and later are comparable.
            if let now = MonthKey.containing(date: today), key >= now { check("Ready to Assign", m.toBeBudgeted, ours.readyToAssign) }
            for c in m.categories {
                guard let cat = byYNAB[c.id], cat.kind != .readyToAssign, let cm = ours.categories[cat.id] else { continue }
                check("\(cat.name): assigned", c.budgeted, cm.assigned)
                check("\(cat.name): activity", c.activity, cm.activity)
                if cat.kind != .cardInterest { check("\(cat.name): available", c.balance, cm.available) }
            }
        }
        // The opening adjustment exists only to square Ready to Assign; it is not a real movement of money, so balances ignore it.
        let all = try transactions().filter { $0.id != "ynab-opening-rta-plug" }
        for a in snapshot.accounts where !a.deleted {
            guard let acct = try accounts().first(where: { $0.ynabID == a.id }) else {
                out.append(YNABDifference(scope: "accounts", subject: "\(a.name): missing here", ynab: a.balance, coinbox: 0)); continue
            }
            let balance = all.filter { $0.accountID == acct.id }.reduce(Milliunits(0)) { $0 + $1.amount }
            if balance != a.balance { out.append(YNABDifference(scope: "accounts", subject: "\(a.name): balance", ynab: a.balance, coinbox: balance)) }
        }
        return out
    }
}
