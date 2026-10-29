import AppKit
import SwiftUI

@main
struct DriftApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var libraryWindow: NSWindow?
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Development/GUI tests can use an isolated library without touching
        // the user's videos or preferences. Normal launches leave this unset.
        let isolatedDirectory = ProcessInfo.processInfo.environment["DRIFT_LIBRARY_DIRECTORY"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        model = AppModel(directory: isolatedDirectory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wind", accessibilityDescription: model.text("app.accessibility"))
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        model.onLanguageChange = { [weak self] in self?.configureMainMenu() }
        configureMainMenu()
        model.start()
        // Login-item launches restore wallpaper without opening a library window.
        let isLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !isLogin { showLibrary() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLibrary(); return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { model?.engine.stop() }

    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(title: "Drift", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Drift")
        add(model.text("menu.open"), action: #selector(showLibrary), key: "1", to: appMenu)
        appMenu.addItem(.separator())
        add(model.text("menu.quit"), action: #selector(quit), key: "q", to: appMenu)
        appItem.submenu = appMenu
        main.addItem(appItem)
        let fileItem = NSMenuItem(title: model.text("menu.file"), action: nil, keyEquivalent: "")
        let file = NSMenu(title: model.text("menu.file"))
        add(model.text("menu.add"), action: #selector(importVideo), key: "o", to: file)
        file.addItem(NSMenuItem(title: model.text("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = file
        main.addItem(fileItem)
        NSApp.mainMenu = main
        statusItem.button?.setAccessibilityLabel(model.text("app.accessibility"))
    }

    @objc private func showLibrary() {
        if libraryWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 780),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Drift"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(red: 0.055, green: 0.065, blue: 0.085, alpha: 1)
            window.contentView = NSHostingView(rootView: LibraryView(model: model).padding(.top, 28))
            window.minSize = NSSize(width: 970, height: 740)
            window.center()
            libraryWindow = window
        }
        libraryWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        statusItem.button?.setAccessibilityLabel(model.text("app.accessibility"))
        let title = NSMenuItem(title: "Drift · \(model.statusSummary)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        add(model.text("menu.open"), action: #selector(showLibrary), key: "o", to: menu)
        add(model.text("menu.add"), action: #selector(importVideo), to: menu)
        add(model.text(model.settings.manuallyPaused ? "action.resume" : "action.pause"), action: #selector(togglePause), key: "p", to: menu)
        add(model.text("action.turnOff"), action: #selector(turnOff), to: menu)
        menu.addItem(.separator())
        add(model.text("menu.quit"), action: #selector(quit), key: "q", to: menu)
    }

    private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    @objc private func importVideo() { showLibrary(); model.chooseVideos() }
    @objc private func togglePause() { model.update { $0.manuallyPaused.toggle() } }
    @objc private func turnOff() { model.update { $0.selectedID = nil } }
    @objc private func quit() { NSApp.terminate(nil) }
}
