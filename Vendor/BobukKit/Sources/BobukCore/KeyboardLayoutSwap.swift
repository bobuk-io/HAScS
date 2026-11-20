// Text typed on the wrong keyboard layout. Shared by Ting launcha search and the lowkey address prompt.
import Foundation

/// Text typed with the wrong keyboard layout: the same physical keys on the US layout and on
/// the Russian or Ukrainian layout (ЙЦУКЕН, as on macOS "Russian - PC" and "Ukrainian - PC").
public enum KeyboardLayoutSwap {
    /// US key → Russian letter.
    private static let russian: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ",
        "p": "з", "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р",
        "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м",
        "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю", "`": "ё",
    ]
    /// US key → Ukrainian letter where it differs from Russian.
    private static let ukrainianDifferences: [Character: Character] = [
        "s": "і", "]": "ї", "'": "є",
    ]
    private static let ukrainian: [Character: Character] = russian.merging(ukrainianDifferences) { $1 }
    /// Cyrillic letter → US key, for both layouts.
    private static let latin: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (key, letter) in ukrainian { map[letter] = key }
        for (key, letter) in russian { map[letter] = key }
        return map
    }()

    /// The lower-cased query first, then each distinct re-typed version:
    /// Cyrillic letters on US keys ("ыфафкш" → "safari") and US keys on the Russian and
    /// Ukrainian layouts ("ntktuhfv" → "телеграм"). Characters without a mapping stay.
    public static func variants(of query: String) -> [String] {
        let lower = query.lowercased()
        var result = [lower]
        for map in [latin, russian, ukrainian] {
            var changed = false
            let converted = String(lower.map { character -> Character in
                guard let mapped = map[character] else { return character }
                changed = true
                return mapped
            })
            if changed, !result.contains(converted) { result.append(converted) }
        }
        return result
    }
}
