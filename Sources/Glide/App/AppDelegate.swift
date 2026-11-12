import AppKit
import Combine
import GlideCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let store = SettingsStore.shared
    private let engine = GlideEngine.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = ProcessInfo.processInfo.arguments
        setUpStatusItem()

        store.$settings
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] visible in self?.statusItem.isVisible = visible }
            .store(in: &cancellables)
        engine.$isRunning.combineLatest(store.$settings.map(\.enabled))
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)

        engine.bootstrap(promptForAccess: !args.contains("--no-prompt"))

        if args.contains("--show-settings") || !engine.isTrusted {
            let tab = args.firstIndex(of: "--tab").flatMap { i in args.indices.contains(i + 1) ? args[i + 1] : nil }
            showSettings(tab: tab.flatMap(SettingsTab.init(rawValue:)))
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(tab: nil)
        return true
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = .removalAllowed
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let active = engine.isRunning && store.settings.enabled
        let image = NSImage(systemSymbolName: active ? "computermouse.fill" : "computermouse",
                            accessibilityDescription: "Glide")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.appearsDisabled = !active
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = store.settings
        let status: String
        if !engine.isTrusted { status = "Needs Accessibility access" }
        else if !s.enabled { status = "Paused" }
        else { status = "Active" }
        let header = NSMenuItem(title: "Glide — \(status)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if engine.otherMouseAppRunning {
            let warn = NSMenuItem(title: "⚠︎ Another mouse utility is running", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())
        menu.addItem(toggle("Enable Glide", s.enabled) { $0.enabled.toggle() })
        menu.addItem(toggle("Smooth Scrolling", s.scrollEnabled) { $0.scrollEnabled.toggle() })
        menu.addItem(toggle("Button Actions", s.buttonsEnabled) { $0.buttonsEnabled.toggle() })
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Glide", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func toggle(_ title: String, _ on: Bool, _ change: @escaping (inout GlideSettings) -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title) { [weak self] in
            guard let self else { return }
            var s = self.store.settings
            change(&s)
            self.store.settings = s
        }
        item.state = on ? .on : .off
        return item
    }

    @objc private func openSettings() { showSettings(tab: nil) }

    // MARK: Settings window

    func showSettings(tab: SettingsTab?) {
        if settingsWindow == nil {
            let root = SettingsView(initialTab: tab ?? .general)
                .environmentObject(store)
                .environmentObject(engine)
            let host = NSHostingController(rootView: root)
            let w = NSWindow(contentViewController: host)
            w.title = "Glide"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 640, height: 660))
            w.center()
            w.setFrameAutosaveName("GlideSettings")
            settingsWindow = w
        } else if let tab {
            NotificationCenter.default.post(name: .glideSelectTab, object: tab)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let glideSelectTab = Notification.Name("GlideSelectTab")
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}
