import CoinboxCore
import SwiftUI

enum Fmt {
    /// The amount as typed into a field: "1234.50", no symbols.
    static func edit(_ m: Milliunits) -> String {
        let cents = Money.divideRounded(abs(m), 10)
        return (m < 0 && cents > 0 ? "-" : "") + "\(cents / 100)." + String(format: "%02d", cents % 100)
    }

    /// "$1,234.56", "-5", "12" → milliunits; nil if it isn't a plain amount.
    static func parse(_ s: String) -> Milliunits? {
        let t = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return SimpleFIN.parseAmount(t.isEmpty ? "0" : t)
    }

    static func shortDate(_ iso: String) -> String {
        guard iso.count == 10, let m = Int(iso.dropFirst(5).prefix(2)), let d = Int(iso.suffix(2)), (1...12).contains(m) else { return iso }
        return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1] + " \(d)"
    }

    static func today() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }

    static func date(_ iso: String) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? Date()
    }

    static func iso(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
}

/// A rounded value chip: Available amounts, status marks.
struct Pill: View {
    let text: String
    let fill: Color
    var foreground: Color = Theme.background
    var body: some View {
        Text(text)
            .font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(fill))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(14).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }
}

struct AmountField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        TextField(title, text: $text).multilineTextAlignment(.trailing).monospacedDigit().frame(minWidth: 90)
    }
}

/// Category choices grouped by their group, for pickers.
struct CategoryPicker: View {
    @Environment(AppModel.self) private var model
    let title: String
    @Binding var selection: String?
    var allowNone = true
    var includeCards = true

    var body: some View {
        Picker(title, selection: $selection) {
            if allowNone { Text("None").tag(String?.none) }
            ForEach(model.planGroups, id: \.group.id) { entry in
                let cats = entry.categories.filter { includeCards || $0.kind == .normal || entry.group.id != CategoryGroup.cardPaymentsID }
                if !cats.isEmpty {
                    Section(entry.group.name) { ForEach(cats, id: \.id) { Text($0.name).tag(String?.some($0.id)) } }
                }
            }
            if allowNone || selection == CoinboxCore.Category.readyToAssignID { Section("Inflow") { Text("Ready to Assign").tag(String?.some(CoinboxCore.Category.readyToAssignID)) } }
        }
    }
}

extension CoinboxCore.Transaction: @retroactive Identifiable {}
extension CoinboxCore.Category: @retroactive Identifiable {}
extension CategoryGroup: @retroactive Identifiable {}
