// ⌘ key equivalents in panels of accessory (LSUIElement) apps. Such an app has no live Edit menu
// while it is not active, so ⌘C/⌘V/⌘X/⌘A/⌘Z must be sent to the text field here, matched by the
// Latin layout so they also work with Russian or Ukrainian input; every other ⌘ shortcut is
// swallowed so that ⌘Q never quits the app from a panel. From Ting's launcha and micro-app panels.
import AppKit
import BobukCore
import BobukSystem

public enum EditCommand: Equatable {
    /// No ⌘: normal key handling.
    case notCommand
    /// ⌘ with arrows, ⌫ or ⌦ (also with ⇧ or ⌥): line-edge movement and deletion in the editor.
    case editor
    /// A text command for the responder chain: cut, copy, paste, select all, undo, redo.
    case text(Selector)
    /// ⌘W.
    case close
    /// ⌘↩ or ⌘Enter with no other modifier.
    case commandReturn
    /// Any other ⌘ shortcut, including ⌘Q.
    case other

    public static func classify(keyCode: UInt16, latin: String?, flags: NSEvent.ModifierFlags) -> EditCommand {
        let flags = flags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command) else { return .notCommand }
        if VirtualKey.textEditing.contains(keyCode) { return .editor }
        if VirtualKey.isReturn(keyCode) { return flags == .command ? .commandReturn : .other }
        switch (latin ?? "", flags) {
        case ("x", .command): return .text(#selector(NSText.cut(_:)))
        case ("c", .command): return .text(#selector(NSText.copy(_:)))
        case ("v", .command): return .text(#selector(NSText.paste(_:)))
        case ("a", .command): return .text(#selector(NSText.selectAll(_:)))
        case ("z", .command): return .text(Selector(("undo:")))
        case ("z", [.command, .shift]): return .text(Selector(("redo:")))
        case ("w", .command): return .close
        default: return .other
        }
    }

    /// Sends a text command along this window's responder chain (not the key window's): the first
    /// responder, its superviews, the window and its delegate. True when someone handled it.
    @MainActor @discardableResult
    public static func send(_ selector: Selector, in window: NSWindow) -> Bool {
        if let responder = window.firstResponder, responder.tryToPerform(selector, with: window) { return true }
        return NSApp.sendAction(selector, to: nil, from: window)
    }

    /// Classifies a key event with the Latin character of its key.
    @MainActor public static func classify(_ event: NSEvent) -> EditCommand {
        classify(keyCode: event.keyCode, latin: KeyEquivalent.latin(of: event), flags: event.modifierFlags)
    }
}

public enum KeyEquivalent {
    /// The character of the ASCII-capable layout for the event's key: "v" for ⌘М on Russian.
    @MainActor public static func latin(of event: NSEvent) -> String? {
        KeyTranslator.latin(event.keyCode) ?? event.charactersIgnoringModifiers?.lowercased()
    }

    /// True for exactly ⌘ plus the key that types `latin` on the ASCII-capable layout.
    @MainActor public static func isCommand(_ event: NSEvent, latin: String) -> Bool {
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            && Self.latin(of: event) == latin
    }

    /// True when the first responder is composing text in an input method (marked text):
    /// Return and arrows belong to the input method then.
    @MainActor public static func isComposing(in window: NSWindow?) -> Bool {
        (window?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }
}
