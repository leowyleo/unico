import SwiftUI

@main
struct UnicoApp: App {
    @StateObject private var settings: ScanSettings
    @StateObject private var model: AppModel

    init() {
        let settings = ScanSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 940, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .newItem) {
                Button(model.t("新扫描", "New Scan")) { model.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.busy)
            }
        }

        Settings {
            SettingsView(settings: settings, language: model.language)
        }
    }
}
