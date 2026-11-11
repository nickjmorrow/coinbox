import Foundation

public enum RuleEngine {
    static func matches(_ m: TextMatch, _ haystack: String) -> Bool {
        switch m.mode {
        case .contains: return haystack.range(of: m.text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .equals: return haystack.compare(m.text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        case .regex:
            guard let re = try? NSRegularExpression(pattern: m.text, options: [.caseInsensitive]) else { return false }
            return re.firstMatch(in: haystack, range: NSRange(haystack.startIndex..., in: haystack)) != nil
        }
    }

    /// True when `text` is not a valid regular expression (so a rule using it can never match).
    public static func isBrokenRegex(_ m: TextMatch?) -> Bool {
        guard let m, m.mode == .regex else { return false }
        return (try? NSRegularExpression(pattern: m.text)) == nil
    }

    public static func matches(_ r: Rule, _ t: Transaction, payeeName: String? = nil) -> Bool {
        if let p = r.payee, !matches(p, t.rawPayee ?? payeeName ?? "") { return false }
        if let mm = r.memo, !matches(mm, t.memo ?? "") { return false }
        if !r.accountIDs.isEmpty, !r.accountIDs.contains(t.accountID) { return false }
        if let a = r.amount {
            switch a {
            case let .equals(v): if t.amount != v { return false }
            case let .range(lo, hi): if t.amount < lo || t.amount > hi { return false }
            case let .endsWithCents(c): if Int(abs(t.amount) / 10 % 100) != c { return false }
            }
        }
        return true
    }

    /// The first rule, in list order, that matches.
    public static func firstMatch(_ rules: [Rule], for t: Transaction, payeeName: String? = nil) -> Rule? {
        rules.sorted { ($0.order, $0.id) < ($1.order, $1.id) }.first { matches($0, t, payeeName: payeeName) }
    }
}
