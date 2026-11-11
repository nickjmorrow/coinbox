import Foundation

/// A calendar month, written "YYYY-MM".
public struct MonthKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    public init?(_ string: String) {
        guard string.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil,
              let y = Int(string.prefix(4)), let m = Int(string.suffix(2)), (1...12).contains(m) else { return nil }
        self.init(year: y, month: m)
    }

    public var string: String { String(format: "%04d-%02d", year, month) }
    public var description: String { string }
    public static func < (a: MonthKey, b: MonthKey) -> Bool { (a.year, a.month) < (b.year, b.month) }

    public func adding(months n: Int) -> MonthKey { MonthKey(year: year, month: month + n) }
    public var next: MonthKey { adding(months: 1) }
    public var previous: MonthKey { adding(months: -1) }

    public var firstDay: String { string + "-01" }
    public var dayCount: Int { Self.daysIn(year: year, month: month) }
    public var lastDay: String { string + "-" + String(format: "%02d", dayCount) }

    public static func containing(date: String) -> MonthKey? { isValidDate(date) ? MonthKey(String(date.prefix(7))) : nil }

    /// This month through `end`, inclusive; empty if `end` is earlier.
    public func monthsThrough(_ end: MonthKey) -> [MonthKey] {
        let n = (end.year - year) * 12 + (end.month - month)
        return n < 0 ? [] : (0...n).map { adding(months: $0) }
    }

    /// How many days in this month fall on `isoWeekday` (1 = Monday ... 7 = Sunday).
    public func weekdayCount(_ isoWeekday: Int) -> Int {
        (1...dayCount).filter { Self.isoWeekday(year: year, month: month, day: $0) == isoWeekday }.count
    }

    public static func isValidDate(_ s: String) -> Bool {
        guard s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let y = Int(s.prefix(4)), let m = Int(s.dropFirst(5).prefix(2)), let d = Int(s.suffix(2)),
              (1...12).contains(m) else { return false }
        return (1...daysIn(year: y, month: m)).contains(d)
    }

    static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Sakamoto's method, shifted so Monday is 1.
    static func isoWeekday(year: Int, month: Int, day: Int) -> Int {
        let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
        let y = month < 3 ? year - 1 : year
        let sundayZero = (y + y / 4 - y / 100 + y / 400 + t[month - 1] + day) % 7
        return sundayZero == 0 ? 7 : sundayZero
    }
}

extension MonthKey {
    /// The calendar day before `date` ("2026-01-01" → "2025-12-31").
    public static func dayBefore(_ date: String) -> String {
        guard isValidDate(date), let y = Int(date.prefix(4)), let m = Int(date.dropFirst(5).prefix(2)), let d = Int(date.suffix(2)) else { return date }
        if d > 1 { return String(format: "%04d-%02d-%02d", y, m, d - 1) }
        let prev = MonthKey(year: y, month: m).previous
        return prev.lastDay
    }
}

extension MonthKey {
    /// Whole days since 1970-01-01 for a valid "YYYY-MM-DD" (so two dates can be subtracted).
    public static func dayNumber(_ date: String) -> Int? {
        guard isValidDate(date), var y = Int(date.prefix(4)), let m = Int(date.dropFirst(5).prefix(2)), let d = Int(date.suffix(2)) else { return nil }
        // Days from civil (Howard Hinnant's algorithm).
        y -= m <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
