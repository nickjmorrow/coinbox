import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: Date(), snapshot: context.isPreview ? .placeholder : WidgetSnapshot.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app asks for a reload after every sync; this is only the fallback.
        completion(Timeline(entries: [Entry(date: Date(), snapshot: WidgetSnapshot.read())], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private let ink = Color(red: 0.039, green: 0.043, blue: 0.098)
private let ember = Color(red: 1, green: 0.54, blue: 0.24)
private let mint = Color(red: 0.37, green: 0.89, blue: 0.71)
private let rose = Color(red: 1, green: 0.36, blue: 0.54)
private let dim = Color(red: 0.65, green: 0.67, blue: 0.81)

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        Group {
            if let s = entry.snapshot { content(s) } else { Text("Open Coinbox to set up").font(.footnote).foregroundStyle(dim) }
        }
        .containerBackground(ink, for: .widget)
    }

    @ViewBuilder private func content(_ s: WidgetSnapshot) -> some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to Assign").font(.caption2).foregroundStyle(dim)
                Text(WidgetSnapshot.dollars(s.readyToAssign)).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(s.readyToAssign < 0 ? rose : mint).minimumScaleFactor(0.6).lineLimit(1)
                Spacer(minLength: 2)
                Text("Runway").font(.caption2).foregroundStyle(dim)
                Text(s.runwayMonths.map { String(format: "%.1f months", $0) } ?? "no targets").font(.headline).foregroundStyle(ember)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to Assign").font(.caption2).foregroundStyle(dim)
                    Text(WidgetSnapshot.dollars(s.readyToAssign)).font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(s.readyToAssign < 0 ? rose : mint).minimumScaleFactor(0.6).lineLimit(1)
                    Spacer(minLength: 2)
                    Text("Runway").font(.caption2).foregroundStyle(dim)
                    Text(s.runwayMonths.map { String(format: "%.1f months", $0) } ?? "no targets").font(.headline).foregroundStyle(ember)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if s.lines.isEmpty { Text("Pin categories in the app").font(.footnote).foregroundStyle(dim) }
                    ForEach(s.lines.prefix(4), id: \.name) { l in
                        HStack { Text(l.name).font(.footnote).foregroundStyle(.white).lineLimit(1); Spacer(); Text(WidgetSnapshot.dollars(l.available)).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(l.overspent ? rose : mint) }
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

@main
struct CoinboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CoinboxWidget", provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Coinbox")
            .description("Ready to Assign, runway, and the categories you pin.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
