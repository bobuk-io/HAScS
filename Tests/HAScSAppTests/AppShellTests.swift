import AppKit
import SwiftUI
import XCTest
import BobukCore
import BobukUI
import HAScSCore
@testable import HAScS

private final class NoCredentials: CredentialStorage {
    func read() throws -> Configuration? { nil }
    func save(_ configuration: Configuration) throws { XCTFail("Must not save credentials") }
}

/// Records paste without reading the user's pasteboard.
private final class PasteRecorder: NSTextView {
    var pastes = 0
    override func paste(_ sender: Any?) { pastes += 1 }
}

@MainActor final class AppShellTests: XCTestCase {
    func testSceneKeysMatchThePhysicalDigitMapOfEarlierVersions() {
        // The hand-written map before BobukKit: top-row and keypad 1–9; 0 runs nothing.
        let previous: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                       83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]
        for code in UInt16(0)...UInt16(255) {
            XCTAssertEqual(SceneKeys.number(forKeyCode: code), previous[code], "key code \(code)")
        }
        XCTAssertEqual(VirtualKey.comma, 43) // ⌘, opens Settings by the physical key.
    }

    func testScenePanelKeepsItsWindowBehavior() {
        let panel = AppDelegate.makeScenePanel()
        defer { panel.close() }
        XCTAssertEqual(panel.kind, .floating)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]))
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertTrue(panel.dismissesOnResignKey)
        XCTAssertTrue(panel.dismissesOnEscape)
        XCTAssertTrue(panel.dismissesOnCommandW)
        XCTAssertEqual(panel.frame.size, NSSize(width: 622, height: 505))
        XCTAssertFalse(panel.isVisible)
    }

    func testSettingsWindowIsAFixedChromeWindowSizedForTheForm() {
        let window = AppDelegate.makeSettingsWindow()
        defer { window.close() }
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.closesOnCommandW)
        XCTAssertFalse(window.title.isEmpty)
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.body.frame.width, 540, accuracy: 0.5)
        XCTAssertEqual(window.body.frame.height, 485, accuracy: 0.5)
        XCTAssertFalse(window.isVisible)
    }

    private func command(_ characters: String, keyCode: UInt16, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, characters: characters,
                                       charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { subview -> [NSTextField] in
            let own = (subview as? NSTextField).map { $0.isEditable ? [$0] : [] } ?? []
            return own + textFields(in: subview)
        }
    }

    /// The app has no main menu, so ⌘V/⌘A in the URL and token fields rely on ChromeWindow.
    func testSettingsFieldsReceiveEditCommandsWithoutAnEditMenu() throws {
        _ = NSApplication.shared
        let suite = "io.bobuk.HAScS.settings.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = ConfigurationRepository(storage: NoCredentials(), defaults: defaults) { throw ConfigurationError.notFound }
        let window = AppDelegate.makeSettingsWindow()
        defer { window.close() }
        window.setContent(SettingsView(repository: repository, onSaved: {}, onCancel: {}))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.routesEditCommands)

        // ⌘A selects the server URL in the real SwiftUI field.
        let field = try XCTUnwrap(textFields(in: window.body).first { !($0 is NSSecureTextField) })
        field.stringValue = "https://ha.example"
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(window.performKeyEquivalent(with: try command("a", keyCode: 0, in: window)))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 18))

        // ⌘V, also typed as ⌘М on a Cyrillic layout, pastes into the focused field.
        let recorder = PasteRecorder(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        window.body.addSubview(recorder)
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(window.performKeyEquivalent(with: try command("v", keyCode: 9, in: window)))
        XCTAssertTrue(window.performKeyEquivalent(with: try command("м", keyCode: 9, in: window)))
        XCTAssertEqual(recorder.pastes, 2)
        XCTAssertFalse(window.isVisible)
    }
}
