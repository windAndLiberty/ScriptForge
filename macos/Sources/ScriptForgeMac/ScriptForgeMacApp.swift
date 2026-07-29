import SwiftUI

@main
struct ScriptForgeMacApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var localization = LocalizationStore()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(model)
                .environmentObject(localization)
                .frame(minWidth: 1_080, minHeight: 720)
        }
        .defaultSize(width: 1_440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
