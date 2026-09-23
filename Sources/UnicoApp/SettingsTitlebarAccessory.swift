import AppKit
import SwiftUI

// SwiftUI's compact hidden-title toolbar keeps a single primary action beside
// the traffic lights. This public titlebar accessory is used only to honor the
// product's explicit right-aligned Settings affordance.
struct SettingsTitlebarAccessory: NSViewRepresentable {
    let settings: ScanSettings
    let language: AppLanguage
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        SettingsWindowPresenter.shared.configure(settings: settings, language: language)
        context.coordinator.setLanguage(language)
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        SettingsWindowPresenter.shared.configure(settings: settings, language: language)
        context.coordinator.setLanguage(language)
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private weak var button: NSButton?
        private var accessory: NSTitlebarAccessoryViewController?
        private var language: AppLanguage = .english

        func setLanguage(_ language: AppLanguage) {
            self.language = language
            let title = language.text("设置", "Settings")
            button?.toolTip = title
            button?.setAccessibilityLabel(title)
        }

        func attach(to candidate: NSWindow?) {
            guard let candidate, window !== candidate else { return }
            detach()

            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
            let title = language.text("设置", "Settings")
            button.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
            button.imagePosition = .imageOnly
            button.bezelStyle = .toolbar
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.target = self
            button.action = #selector(showSettings)

            let controller = NSTitlebarAccessoryViewController()
            controller.view = button
            controller.layoutAttribute = .right
            candidate.addTitlebarAccessoryViewController(controller)
            window = candidate
            self.button = button
            accessory = controller
        }

        func detach() {
            if let accessory, let index = window?.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
                window?.removeTitlebarAccessoryViewController(at: index)
            }
            accessory = nil
            button = nil
            window = nil
        }

        @objc private func showSettings() {
            SettingsWindowPresenter.shared.show()
        }
    }
}

final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()
    private weak var window: NSWindow?
    private var settings: ScanSettings?
    private var language: AppLanguage = .english

    func configure(settings: ScanSettings, language: AppLanguage) {
        self.settings = settings
        self.language = language
    }

    func show() {
        guard let settings else { return }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 570),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = language.text("设置", "Settings")
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, language: language))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }
}
