import AppKit
import Testing
import BobukUI

/// Subclasses in app modules capture `[weak self]` in notification blocks without warnings.
@MainActor final class ProbeWindow: ChromeWindow {
    var observer: NSObjectProtocol?
    func observe() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.title }
        }
    }
}

@MainActor final class ProbePanel: BobukPanel {
    var observer: NSObjectProtocol?
    func observe() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.title }
        }
    }
}

@MainActor @Suite struct SubclassSendableTests {
    @Test func subclassesCompile() {
        let window = ProbeWindow(contentRect: .zero)
        let panel = ProbePanel(kind: .floating)
        window.observe()
        panel.observe()
        #expect(window.observer != nil && panel.observer != nil)
    }
}
