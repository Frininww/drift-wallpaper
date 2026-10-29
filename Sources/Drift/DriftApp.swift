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
        model = AppModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Drift — живые обои")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
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
        let title = NSMenuItem(title: "Drift · \(model.statusSummary)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        add("Открыть Drift…", action: #selector(showLibrary), key: "o", to: menu)
        add("Добавить видео…", action: #selector(importVideo), to: menu)
        add(model.settings.manuallyPaused ? "Продолжить" : "Пауза", action: #selector(togglePause), key: "p", to: menu)
        add("Выключить обои", action: #selector(turnOff), to: menu)
        menu.addItem(.separator())
        add("Завершить Drift", action: #selector(quit), key: "q", to: menu)
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
