import Foundation

/// Dollars in thousandths, as YNAB's API uses, so imports compare exactly.
public typealias Milliunits = Int64

public enum Money {
    /// `$1,234.56`; negative amounts read `-$12.30`. Rounds to the cent, half away from zero.
    public static func format(_ m: Milliunits) -> String {
        let cents = divideRounded(abs(m), 10)
        let dollars = String(cents / 100)
        var grouped = ""
        for (i, ch) in dollars.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        let rest = cents % 100
        return (m < 0 && cents > 0 ? "-" : "") + "$" + String(grouped.reversed()) + "." + (rest < 10 ? "0" : "") + String(rest)
    }

    /// Integer division rounding half away from zero.
    public static func divideRounded(_ numerator: Int64, _ denominator: Int64) -> Int64 {
        let q = numerator / denominator, r = numerator % denominator
        return abs(r) * 2 >= abs(denominator) ? q + ((numerator < 0) == (denominator < 0) ? 1 : -1) : q
    }
}
