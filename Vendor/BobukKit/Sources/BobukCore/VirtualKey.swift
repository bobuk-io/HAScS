// Physical key codes that panels and key handlers compare against. Named here once so that apps
// never repeat magic numbers such as 53 or 126.
import Foundation

/// macOS virtual key codes (`NSEvent.keyCode`, Carbon `kVK_*`) for keys handled by name.
/// Letters and digits depend on the layout: match them with `KeyTranslator.latin`, not here.
public enum VirtualKey {
    public static let returnKey: UInt16 = 36
    public static let keypadEnter: UInt16 = 76
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let forwardDelete: UInt16 = 117
    public static let home: UInt16 = 115
    public static let end: UInt16 = 119
    public static let pageUp: UInt16 = 116
    public static let pageDown: UInt16 = 121
    public static let left: UInt16 = 123
    public static let right: UInt16 = 124
    public static let down: UInt16 = 125
    public static let up: UInt16 = 126
    /// The physical comma key of ⌘, (Settings). A key code, so it stays ⌘, on Cyrillic layouts.
    public static let comma: UInt16 = 43

    /// Return or keypad Enter.
    public static func isReturn(_ code: UInt16) -> Bool { code == returnKey || code == keypadEnter }

    /// Arrows, ⌫ and ⌦: with ⌘ they move or delete to a line edge and belong to the text editor.
    public static let textEditing: Set<UInt16> = [delete, forwardDelete, left, right, down, up]

    /// Physical digit keys of the top row, 1...9 then 0, independent of the layout
    /// (AZERTY and Cyrillic layouts produce other characters on them).
    public static let topRowDigits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0]
    /// Keypad digits 0...9.
    public static let keypadDigits: [UInt16: Int] = [82: 0, 83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]

    /// The digit of a top-row or keypad key, whatever the layout.
    public static func digit(_ code: UInt16) -> Int? { topRowDigits[code] ?? keypadDigits[code] }
}
