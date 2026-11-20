import AppKit
import SwiftUI
import BobukCore
import BobukSystem
import BobukUI
import HAScSCore

/// Scene keys of the panel.
enum SceneKeys {
    /// The scene number of a physical 1–9 key, top row or keypad, with any keyboard layout.
    /// 0 selects nothing.
    static func number(forKeyCode keyCode: UInt16) -> Int? {
        guard let digit = VirtualKey.digit(keyCode), (1...9).contains(digit) else { return nil }
        return digit
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: SceneStore
    private var statusItem: NSStatusItem!
    private var panel: BobukPanel!
    private var settings: HostedWindowController!
    private var keyMonitor: Any?
    private var refreshTask: Task<Void, Never>?
    private var presentation = 0
    private var launchFinished = false
    private var pendingOpen = false

    override convenience init() {
        self.init(store: SceneStore())
    }

    init(store: SceneStore) {
        self.store = store
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppActivation.becomeAccessory()
        configureStatusItem()
        configurePanel()
        configureSettings()
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
        settings.show()
    }

    /// A fixed-size ChromeWindow whose body fits the 540×485 SettingsView. ⌘C/⌘V/⌘X/⌘A/⌘Z reach
    /// its fields without an Edit menu (`routesEditCommands`).
    static func makeSettingsWindow() -> ChromeWindow {
        let size = ChromeMetrics.windowSize(forBody: NSSize(width: 540, height: 485))
        let window = ChromeWindow(contentRect: NSRect(origin: .zero, size: size),
                                  style: RemoteStyle.palette.chromeStyle, resizable: false, showsTitle: true)
        window.title = L10n.string("HAScS Settings")
        return window
    }

    private func configureSettings() {
        let store = self.store
        // The SecureField and any unsaved token are released when the window closes.
        settings = HostedWindowController(releasesContentOnClose: true, window: Self.makeSettingsWindow, rootView: { [weak self] in
            SettingsView(
                repository: store.configuration,
                onSaved: { [weak self] in
                    self?.refreshTask?.cancel()
                    store.invalidateConfiguration()
                    self?.settings.close()
                },
                onCancel: { [weak self] in self?.settings.close() }
            )
        })
    }

    /// The floating, non-activating scene panel on every Space; it may become main for the grid.
    static func makeScenePanel() -> BobukPanel {
        let panel = BobukPanel(contentRect: NSRect(x: 0, y: 0, width: 622, height: 505), kind: .floating)
        panel.title = L10n.string("Home scenes — HAScS")
        panel.allowsMain = true
        panel.collectionBehavior.insert(.transient)
        return panel
    }

    private func configurePanel() {
        let panel = Self.makeScenePanel()
        // Focus loss and ⌘W close the panel through BobukPanel. Clicking another application
        // dismisses this quick launcher, but never attempts to cancel an already-sent HA request.
        panel.onDismiss = { [weak self] _ in self?.hidePanel() }
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
        panel.place(size: panel.frame.size, anchor: .center())
        AppActivation.activate()
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

    private func configureKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == VirtualKey.comma && modifiers.contains(.command) && !event.isARepeat {
                self.openSettings()
                return nil
            }
            // Other ⌘ shortcuts go to BobukPanel: ⌘W closes, ⌘Q is swallowed.
            guard modifiers.intersection([.command, .control, .option]).isEmpty, !event.isARepeat else { return event }
            if let number = SceneKeys.number(forKeyCode: event.keyCode) {
                if !self.store.isReordering { self.activate(number) }
                return nil
            }
            let direction: SceneGridDirection? = switch event.keyCode {
            case VirtualKey.left: .left
            case VirtualKey.right: .right
            case VirtualKey.up: .up
            case VirtualKey.down: .down
            default: nil
            }
            if let direction {
                if self.store.isReordering && modifiers.contains(.shift) { self.store.moveSelectedScene(direction) }
                else { self.store.moveSelection(direction) }
                return nil
            }
            // Escape cancels reordering before it closes the panel, so it is handled here.
            if event.keyCode == VirtualKey.escape {
                if self.store.isReordering { self.store.finishReordering(save: false) }
                else { self.panel.dismiss(.escape) }
                return nil
            }
            guard VirtualKey.isReturn(event.keyCode) else { return event }
            if self.store.isReordering { self.store.finishReordering(save: true) }
            else if let number = self.store.selectedNumber { self.activate(number) }
            return nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}
