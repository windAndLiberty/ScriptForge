import SwiftUI

@main
struct ScriptForgeMacApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var localization = LocalizationStore()
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(InterfaceScalePolicy.storageKey) private var interfaceScale = InterfaceScalePolicy.defaultValue

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(model)
                .environmentObject(localization)
                .environment(\.interfaceScale, normalizedInterfaceScale)
                .preferredColorScheme(currentAppearance.preferredColorScheme)
                .frame(
                    minWidth: InterfaceScalePolicy.layoutScaled(1_080, by: normalizedInterfaceScale),
                    minHeight: InterfaceScalePolicy.layoutScaled(720, by: normalizedInterfaceScale)
                )
                .onAppear { interfaceScale = normalizedInterfaceScale }
        }
        .defaultSize(width: 1_440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu(localization.text("视图")) {
                Button(localization.text("放大")) {
                    interfaceScale = InterfaceScalePolicy.increase(interfaceScale)
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(normalizedInterfaceScale >= InterfaceScalePolicy.maximum)

                Button(localization.text("缩小")) {
                    interfaceScale = InterfaceScalePolicy.decrease(interfaceScale)
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(normalizedInterfaceScale <= InterfaceScalePolicy.minimum)

                Divider()

                Button(localization.text("实际大小")) {
                    interfaceScale = InterfaceScalePolicy.defaultValue
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(normalizedInterfaceScale == InterfaceScalePolicy.defaultValue)
            }
        }
    }

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var normalizedInterfaceScale: Double {
        InterfaceScalePolicy.normalized(interfaceScale)
    }
}
