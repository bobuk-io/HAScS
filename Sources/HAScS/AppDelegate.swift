import AppKit
import SwiftUI
import HAScSCore

@MainActor
final class RemotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = SceneStore()
    private var statusItem: NSStatusItem!
    private var panel: RemotePanel!
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var refreshTask: Task<Void, Never>?
    private var presentation = 0
    private var launchFinished = false
    private var pendingOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePanel()
        configureKeyMonitor()
        // One-time, read-only legacy import; errors are displayed on the next
        // panel/settings opening and never fall back to plaintext for requests.
        _ = try? store.configuration.load()
        launchFinished = true
        if pendingOpen { showPanel() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: Self.isSceneLink) else { return }
        if launchFinished { showPanel() } else { pendingOpen = true }
    }

    private static func isSceneLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "hascs" && url.host?.lowercased() == "scenes" &&
        (url.path.isEmpty || url.path == "/") && url.user == nil && url.password == nil &&
        url.query == nil && url.fragment == nil
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "house", accessibilityDescription: L10n.string("HAScS — home scenes"))
        button.image?.isTemplate = true
        button.toolTip = L10n.string("HAScS — click for scenes; right-click for menu")
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: L10n.string("Open scenes"), action: #selector(openFromMenu), keyEquivalent: "")
            menu.addItem(withTitle: L10n.string("Settings…"), action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: L10n.string("Quit HAScS"), action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    @objc private func openFromMenu() { showPanel() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() {
        if panel.isVisible { hidePanel() }
        if let settingsWindow, settingsWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 485),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.string("HAScS Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(
            repository: store.configuration,
            onSaved: { [weak self] in
                self?.refreshTask?.cancel()
                self?.store.invalidateConfiguration()
                self?.settingsWindow?.close()
            },
            onCancel: { [weak self] in self?.settingsWindow?.close() }
        ))
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow {
            // Release the SecureField and any unsaved token when the window closes.
            settingsWindow = nil
        }
    }

    private func configurePanel() {
        let panel = RemotePanel(contentRect: NSRect(x: 0, y: 0, width: 622, height: 505),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L10n.string("Home scenes — HAScS")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ScenePanelView(
            store: store,
            activate: { [weak self] number in self?.activate(number) },
            close: { [weak self] in self?.hidePanel() },
            refresh: { [weak self] in self?.refresh() },
            settings: { [weak self] in self?.openSettings() }
        ))
        self.panel = panel
    }

    private func showPanel() {
        presentation += 1
        store.resetTransientState()
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            let rect = panel.frame
            panel.setFrameOrigin(NSPoint(x: area.midX - rect.width / 2, y: area.midY - rect.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        refresh()
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await store.refresh() }
    }

    private func hidePanel() {
        presentation += 1
        panel.orderOut(nil)
        store.resetTransientState()
    }

    private func activate(_ number: Int) {
        let currentPresentation = presentation
        Task {
            guard await store.activate(number: number) else { return }
            try? await Task.sleep(for: .milliseconds(850))
            if presentation == currentPresentation, panel.isVisible { hidePanel() }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another application dismisses this quick launcher, but never
        // attempts to cancel an already-sent HA request.
        if panel.isVisible { hidePanel() }
    }

    private func configureKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 43 && modifiers.contains(.command) && !event.isARepeat {
                self.openSettings()
                return nil
            }
            guard modifiers.intersection([.command, .control, .option]).isEmpty, !event.isARepeat else { return event }
            // Physical digit keys still work with non-Latin keyboard layouts.
            let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]
            if let number = digits[event.keyCode] { self.activate(number); return nil }
            switch event.keyCode {
            case 53: self.hidePanel(); return nil // Escape
            case 126, 123: self.store.moveSelection(-1); return nil // up / left
            case 125, 124: self.store.moveSelection(1); return nil // down / right
            case 36, 76:
                if let number = self.store.selectedNumber { self.activate(number) }
                return nil
            default: return event
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}
