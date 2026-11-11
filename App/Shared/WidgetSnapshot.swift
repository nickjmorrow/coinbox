import Foundation

/// What the home-screen widget shows. The app writes it into the App Group after every change or sync; the widget only reads it.
struct WidgetSnapshot: Codable, Equatable {
    struct Line: Codable, Equatable {
        var name: String
        var available: Int64
        var overspent: Bool
    }

    static let group = "group.com.nicholai.coinbox"
    static let fileName = "widget.json"

    var updated: Date
    var month: String
    var readyToAssign: Int64
    var runwayMonths: Double?
    var lines: [Line]

    static var url: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent(fileName) }

    func write() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static var pinned: [String] {
        get { UserDefaults(suiteName: group)?.stringArray(forKey: "pinned") ?? [] }
        set { UserDefaults(suiteName: group)?.set(Array(newValue.prefix(4)), forKey: "pinned") }
    }

    static func dollars(_ milliunits: Int64) -> String {
        let cents = (abs(milliunits) + 5) / 10
        let whole = cents / 100
        var grouped = ""
        for (i, ch) in String(whole).reversed().enumerated() { if i > 0 && i % 3 == 0 { grouped.append(",") }; grouped.append(ch) }
        return (milliunits < 0 && cents > 0 ? "-" : "") + "$" + String(grouped.reversed()) + (whole < 1000 ? "." + String(format: "%02d", cents % 100) : "")
    }

    static let placeholder = WidgetSnapshot(updated: Date(), month: "2026-01", readyToAssign: 1_240_000, runwayMonths: 3.4,
                                            lines: [Line(name: "Groceries", available: 212_500, overspent: false), Line(name: "Eating out", available: -14_000, overspent: true),
                                                    Line(name: "Fun", available: 60_000, overspent: false), Line(name: "Gas", available: 41_250, overspent: false)])
}
