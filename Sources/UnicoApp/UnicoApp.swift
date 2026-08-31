import AppKit
import SwiftUI

@main
enum UnicoApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate {
    let model = AppModel()
    var window: NSWindow!
    private let languageItem = NSMenuToolbarItem(itemIdentifier: NSToolbarItem.Identifier("Unico.language"))
    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildMenu()
        model.onLanguageChange = { [weak self] in self?.rebuildMenu() }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Unico"
        // Keep the native title bar in the same bright family as the SwiftUI surfaces.
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(calibratedRed: 0.965, green: 0.949, blue: 0.914, alpha: 1)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "Unico.titlebar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        window.contentMinSize = NSSize(width: 940, height: 660)
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.delegate = self
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func rebuildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: model.t("关于 Unico", "About Unico"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let language = NSMenuItem(title: "语言 / Language", action: nil, keyEquivalent: "")
        let languages = NSMenu()
        for (index, choice) in AppLanguage.allCases.enumerated() {
            let item = NSMenuItem(title: choice.name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.tag = index; item.target = self; item.state = model.language == choice ? .on : .off
            languages.addItem(item)
        }
        language.submenu = languages; appMenu.addItem(language)
        languageItem.menu = languages.copy() as! NSMenu
        languageItem.label = model.t("语言", "Language")
        languageItem.toolTip = "语言 / Language"
        languageItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "语言 / Language")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: model.t("隐藏 Unico", "Hide Unico"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: model.t("退出 Unico", "Quit Unico"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: model.t("编辑", "Edit"))
        editMenu.addItem(withTitle: model.t("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: model.t("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: model.t("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = menu
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, languageItem.itemIdentifier]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        identifier == languageItem.itemIdentifier ? languageItem : nil
    }
    @objc func changeLanguage(_ sender: NSMenuItem) {
        guard AppLanguage.allCases.indices.contains(sender.tag) else { return }
        model.language = AppLanguage.allCases[sender.tag]
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.busy { model.cancel() }
        return .terminateNow
    }
}
