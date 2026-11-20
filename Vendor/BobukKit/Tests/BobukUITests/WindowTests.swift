import AppKit
import SwiftUI
import Testing
@testable import BobukUI

/// Windows are created but never shown on screen or activated.
@MainActor @Suite(.serialized) struct ChromeWindowTests {
    final class Delegate: NSObject, NSWindowDelegate {
        var allowClose = true
        var asked = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool { asked += 1; return allowClose }
    }

    private func key(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = .command, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    @Test func closeButtonLivesInTheStripAndUsesPerformClose() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        let delegate = Delegate()
        window.delegate = delegate
        window.orderBack(nil)
        #expect(window.strip.buttons.first === window.closeButton)
        #expect(window.closeButton.glyph == .close)
        #expect(window.closeButton.label == "Close · ⌘W")

        delegate.allowClose = false
        window.closeButton.performPress()
        #expect(delegate.asked == 1)
        #expect(window.isVisible)

        delegate.allowClose = true
        window.closeButton.performPress()
        #expect(delegate.asked == 2)
        #expect(!window.isVisible)
        // NSWindow does not retain its delegate: detach it before the delegate goes away.
        window.delegate = nil
    }

    @Test func commandWClosesAndCanBeTurnedOff() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.orderBack(nil)
        window.closesOnCommandW = false
        #expect(!window.performKeyEquivalent(with: key("w", keyCode: 13, window: window)))
        #expect(window.isVisible)
        window.closesOnCommandW = true
        #expect(window.performKeyEquivalent(with: key("w", keyCode: 13, window: window)))
        #expect(!window.isVisible)
    }

    @Test func layoutAccentStripSeparatorBody() {
        let left = StripButton(glyph: .back, label: "Back")
        let right = StripButton(glyph: .forward, label: "Forward")
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), leading: [left], trailing: [right])
        window.setContent(NSHostingView(rootView: Color.red))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(window.accentBar.frame.height == ChromeMetrics.accentHeight)
        #expect(abs(window.strip.frame.height - ChromeMetrics.stripHeight) < 0.5)
        #expect(window.body.subviews.count == 1)
        #expect(window.strip.buttons.map(\.glyph) == [.close, .back, .forward])
        let leftFrame = left.convert(left.bounds, to: nil), rightFrame = right.convert(right.bounds, to: nil)
        #expect(leftFrame.minX < rightFrame.minX)
        #expect(rightFrame.maxX <= 500)
        window.removeContent()
        #expect(window.body.subviews.isEmpty)
    }

    @Test func editCommandsReachTheTextFieldWithoutAnEditMenu() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200))
        let field = NSTextField(string: "hello")
        field.frame = NSRect(x: 10, y: 10, width: 200, height: 24)
        window.body.addSubview(field)
        window.orderBack(nil)
        #expect(window.makeFirstResponder(field))
        #expect(window.performKeyEquivalent(with: key("a", keyCode: 0, window: window)))
        #expect((field.currentEditor() as? NSTextView)?.selectedRange() == NSRange(location: 0, length: 5))
        // ⌘Q and other commands are left to the app's menu.
        #expect(!window.performKeyEquivalent(with: key("q", keyCode: 12, window: window)))
        // A non-text first responder (a web view) keeps the normal path for edit keys.
        let custom = NSView(frame: NSRect(x: 0, y: 50, width: 50, height: 50))
        window.body.addSubview(custom)
        _ = window.makeFirstResponder(window.contentView)
        #expect(!window.performKeyEquivalent(with: key("a", keyCode: 0, window: window)))
        window.close()
    }

    @Test func chromeHeightSizesTheBody() {
        #expect(ChromeMetrics.chromeHeight() == ChromeMetrics.accentHeight + ChromeMetrics.stripHeight + 1)
        #expect(ChromeMetrics.windowSize(forBody: NSSize(width: 540, height: 485)).height == 485 + ChromeMetrics.chromeHeight())
    }

    @Test func fixedWindowsHaveNoResizeOrFullScreen() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), resizable: false, showsTitle: true)
        window.title = "Demo Settings"
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(!window.strip.handlesDoubleClick)
        #expect(window.strip.title == "Demo Settings")
    }

    @Test func stripButtonColorsFollowTheWindowStyle() {
        let style = ChromeStyle(panel: .white, ink: .black, muted: .gray, accent: .orange, separator: .lightGray)
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), style: style)
        #expect(window.closeButton.resolvedStyle == style)
        #expect(window.closeButton.glyphColor() == .gray)
        #expect(window.closeButton.isDestructive)
        var tinted = style
        tinted.destructiveHover = nil
        window.setChromeStyle(tinted)
        #expect(window.closeButton.resolvedStyle.destructiveHover == nil)
        #expect(window.accentBar.color == .orange)
        window.closeButton.isEnabled = false
        var pressed = false
        window.closeButton.onPress = { _ in pressed = true }
        window.closeButton.performPress()
        #expect(!pressed)
    }

    @Test func hostedWindowControllerReleasesContent() {
        var builds = 0
        var closes = 0
        let controller = HostedWindowController(window: { ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200)) },
                                                content: { builds += 1; return NSView() })
        controller.onClose = { closes += 1 }
        controller.show(activate: false)
        let first = controller.window as? ChromeWindow
        #expect(first?.body.subviews.count == 1)
        #expect(controller.isOpen)
        (controller.window as? ChromeWindow)?.closeButton.performPress()
        #expect(controller.window == nil)
        #expect(first?.body.subviews.isEmpty == true)
        #expect(closes == 1)
        controller.show(activate: false)
        #expect(builds == 2)
        controller.close()
    }

    @Test func swiftUIContentStartsRightBelowTheChrome() {
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 223))
        let hosting = window.setContent(Color.red.frame(width: 300, height: 200))
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(hosting.safeAreaRegions.isEmpty)
        #expect(hosting.fittingSize.height == 200)
        #expect(abs(window.body.frame.height - 200) < 0.5)
        #expect(window.contentSize(forBody: NSSize(width: 300, height: 600)).height == 600 + ChromeMetrics.chromeHeight())
    }

    @Test func hostedControllerPreparesWithoutShowingAndFitsContent() {
        let controller = HostedWindowController(window: { ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), resizable: false) },
                                                rootView: { Color.blue.frame(width: 320, height: 180) })
        controller.sizesToFitContent = true
        let window = controller.prepare()
        #expect(!window.isVisible && !controller.isOpen)
        #expect(controller.prepare() === window)
        #expect(abs((window as! ChromeWindow).body.frame.height - 180) < 0.5)
        #expect(abs(window.contentLayoutRect.width - 320) < 0.5)
    }

    @Test func windowReferenceFindsItsHost() {
        let reference = WindowReference()
        let window = ChromeWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.setContent(Color.clear.windowReference(reference))
        window.contentView?.layoutSubtreeIfNeeded()
        window.orderBack(nil)
        #expect(reference.window === window)
        reference.close()
        #expect(!window.isVisible)
    }
}

@MainActor @Suite(.serialized) struct BobukPanelTests {
    @Test func kinds() {
        let launcher = BobukPanel(kind: .launcher)
        #expect(launcher.level == .popUpMenu)
        #expect(launcher.styleMask.contains(.nonactivatingPanel))
        #expect(launcher.collectionBehavior.contains(.stationary))
        #expect(launcher.routesEditCommands)
        #expect(launcher.canBecomeKey && !launcher.canBecomeMain)
        let prompt = BobukPanel(kind: .prompt)
        #expect(!prompt.styleMask.contains(.nonactivatingPanel))
        #expect(prompt.dismissesOnAppDeactivation && !prompt.routesEditCommands)
        let hud = BobukPanel(kind: .hud)
        #expect(hud.ignoresMouseEvents && !hud.canBecomeKey && !hud.dismissesOnResignKey)
    }

    @Test func dismissalIsSuspendedWhileAMenuTracks() {
        let panel = BobukPanel(kind: .floating)
        var reasons: [BobukPanel.DismissReason] = []
        panel.onDismiss = { reasons.append($0); panel.orderOut(nil) }
        panel.orderBack(nil)
        panel.suspendDismissal()
        panel.resignKey()
        #expect(reasons.isEmpty)
        panel.resumeDismissal()
        panel.resignKey()
        panel.orderBack(nil)
        panel.cancelOperation(nil)
        #expect(reasons.contains(.resignedKey) || reasons.contains(.escape))
        #expect(reasons.last == .escape)
    }

    @Test func commandKeysAreRoutedAndSwallowed() {
        let panel = BobukPanel(kind: .launcher)
        var seen: [EditCommand] = []
        panel.onCommandKey = { _, command in seen.append(command); return command == .commandReturn }
        func event(_ c: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = .command) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                             characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)!
        }
        #expect(panel.performKeyEquivalent(with: event("q", 12)))      // ⌘Q swallowed
        #expect(!panel.performKeyEquivalent(with: event("", 123)))     // ⌘← to the editor
        #expect(panel.performKeyEquivalent(with: event("\r", 36)))     // ⌘↩ handled by the app
        #expect(seen == [.other, .editor, .commandReturn])
        // Panels with their own SwiftUI shortcuts let other ⌘ keys through.
        panel.swallowsOtherCommandKeys = false
        #expect(!panel.performKeyEquivalent(with: event("q", 12)))
        #expect(panel.routesEditCommands)
    }
}

@Suite struct EditCommandTests {
    @Test func classification() {
        #expect(EditCommand.classify(keyCode: 9, latin: "v", flags: .command) == .text(#selector(NSText.paste(_:))))
        #expect(EditCommand.classify(keyCode: 6, latin: "z", flags: [.command, .shift]) == .text(Selector(("redo:"))))
        #expect(EditCommand.classify(keyCode: 13, latin: "w", flags: .command) == .close)
        #expect(EditCommand.classify(keyCode: 12, latin: "q", flags: .command) == .other)
        #expect(EditCommand.classify(keyCode: 36, latin: nil, flags: .command) == .commandReturn)
        #expect(EditCommand.classify(keyCode: 36, latin: nil, flags: [.command, .shift]) == .other)
        #expect(EditCommand.classify(keyCode: 51, latin: nil, flags: [.command, .option]) == .editor)
        #expect(EditCommand.classify(keyCode: 9, latin: "v", flags: []) == .notCommand)
        // The physical V key typed with a Cyrillic layout still pastes: the router gets "v".
        #expect(EditCommand.classify(keyCode: 9, latin: "v", flags: [.command, .capsLock]) == .text(#selector(NSText.paste(_:))))
    }
}

@Suite struct GlyphTests {
    @Test func everyGlyphHasAnOutlineInsideItsBox() {
        let box = CGRect(x: 0, y: 0, width: 16, height: 16)
        for glyph in Glyph.allCases {
            let bounds = glyph.path(in: box).boundingBoxOfPath
            #expect(!bounds.isNull && bounds.width + bounds.height > 1, "\(glyph)")
            #expect(box.insetBy(dx: -1, dy: -1).contains(bounds), "\(glyph)")
        }
        #expect(Glyph.close.isDestructive && Glyph.terminate.isDestructive && !Glyph.back.isDestructive)
        #expect(Glyph.lineWidth(for: CGRect(x: 0, y: 0, width: 8, height: 8)) == 0.8)
    }

    @Test func paletteHelpers() {
        let color = NSColor(hex: 0x885500).usingColorSpace(.sRGB)!
        #expect(abs(color.redComponent - 0x88 / 255.0) < 0.001)
        #expect(AppearanceChoice.light.appearance?.name == .aqua)
        #expect(AppearanceChoice.system.appearance == nil)
        let suite = UserDefaults(suiteName: "bobukkit-appearance-\(UUID().uuidString)")!
        #expect(AppearanceChoice.stored(in: suite, key: "theme", fallback: .dark) == .dark)
        suite.set("light", forKey: "theme")
        #expect(AppearanceChoice.stored(in: suite, key: "theme") == .light)
    }
}
