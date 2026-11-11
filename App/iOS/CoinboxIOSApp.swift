import CoinboxUI
import SwiftUI
import WidgetKit

@main
struct CoinboxIOSApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var phase

    init() {
        // The database lives in the App Group so the widget's data and the app's share one home.
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)
            ?? (try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
        do {
            let m = try AppModel.open(path: dir.appendingPathComponent("coinbox.sqlite").path)
            m.widgetDefaults = UserDefaults(suiteName: WidgetSnapshot.group)
            m.reload()
            _model = State(initialValue: m)
        } catch { fatalError("Can't open the Coinbox database: \(error)") }
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView().environment(model)
                .onAppear { model.startWatching(); model.startAutoSync(interval: 120); publish() }
                .onChange(of: model.summary) { _, _ in publish() }
                .onChange(of: model.pinned) { _, _ in publish() }
                .onChange(of: phase) { _, now in if now == .active { Task { await model.syncNow() } } }
        }
    }

    /// Writes what the widget shows and asks it to redraw.
    private func publish() {
        let lines = model.pinned.compactMap { id -> WidgetSnapshot.Line? in
            guard let c = model.category(id), let m = model.summary.categories[id] else { return nil }
            return WidgetSnapshot.Line(name: c.name, available: m.available, overspent: m.available < 0)
        }
        WidgetSnapshot(updated: Date(), month: model.month.string, readyToAssign: model.summary.readyToAssign, runwayMonths: model.runway.months, lines: lines).write()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
