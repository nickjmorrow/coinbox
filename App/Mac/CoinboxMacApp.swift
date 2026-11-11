import CoinboxUI
import SwiftUI

@main
struct CoinboxMacApp: App {
    @State private var model: AppModel

    init() {
        do { _model = State(initialValue: try AppModel.openDefault()) } catch { fatalError("Can't open the Coinbox database: \(error)") }
    }

    var body: some Scene {
        WindowGroup {
            MacRootView().environment(model).onAppear { model.startWatching(); model.startAutoSync() }
        }
        .defaultSize(width: 1280, height: 820)
    }
}
