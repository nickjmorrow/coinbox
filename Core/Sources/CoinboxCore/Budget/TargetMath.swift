import Foundation

public enum TargetMath {
    private static func index(_ m: MonthKey) -> Int { m.year * 12 + m.month - 1 }

    private static func ceilDiv(_ x: Int64, _ d: Int64) -> Int64 { x <= 0 ? 0 : (x + d - 1) / d }

    /// The due date for a dated cadence as seen from `month`: the first occurrence on or after the month's first day,
    /// or (for a by-date target already past) the date itself. Nil for weekly and monthly targets.
    static func due(_ c: Cadence, from month: MonthKey) -> String? {
        func clamp(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, min(d, MonthKey.daysIn(year: y, month: m))) }
        switch c {
        case .weekly, .monthly: return nil
        case let .byDate(d): return d
        case let .yearly(m, d):
            let thisYear = clamp(month.year, m, d)
            return thisYear >= month.firstDay ? thisYear : clamp(month.year + 1, m, d)
        case let .everyMonths(n, firstDue):
            guard let first = MonthKey.containing(date: firstDue), n > 0, let day = Int(firstDue.suffix(2)) else { return firstDue }
            let gap = index(month) - index(first)
            let k = gap <= 0 ? 0 : (gap + n - 1) / n
            let dueMonth = first.adding(months: k * n)
            return clamp(dueMonth.year, dueMonth.month, day)
        }
    }

    private static func monthsLeft(due: String, from month: MonthKey) -> Int64 {
        guard due >= month.firstDay, let dueMonth = MonthKey.containing(date: due) else { return 1 }
        return Int64(max(1, index(dueMonth) - index(month) + 1))
    }

    /// What this target wants set aside in `month`, given the balance carried in.
    public static func needed(_ t: Target, in month: MonthKey, carryover: Milliunits) -> Milliunits {
        switch t.cadence {
        case let .weekly(w): return t.amount * Int64(month.weekdayCount(w))
        case .monthly: return t.amount
        default:
            guard let due = due(t.cadence, from: month) else { return t.amount }
            return ceilDiv(t.amount - carryover, monthsLeft(due: due, from: month))
        }
    }

    /// An average month's cost of this target.
    public static func monthlyNeed(_ t: Target, asOf month: MonthKey) -> Milliunits {
        switch t.cadence {
        case .weekly: return Money.divideRounded(t.amount * 52, 12)
        case .monthly: return t.amount
        case .yearly: return Money.divideRounded(t.amount, 12)
        case let .everyMonths(n, _): return Money.divideRounded(t.amount, Int64(max(1, n)))
        case let .byDate(d): return d < month.firstDay ? 0 : ceilDiv(t.amount, monthsLeft(due: d, from: month))
        }
    }

    public static func costToBeMe(_ targets: [Target], asOf month: MonthKey) -> Milliunits {
        targets.reduce(0) { $0 + monthlyNeed($1, asOf: month) }
    }
}
