// Light/dark colors from hex values, the shared bobuk-io amber palette and the app-wide
// appearance choice. Apps keep their own colors where they differ; identical values live here.
import AppKit
import SwiftUI

public extension NSColor {
    /// An sRGB color from `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    /// A color that follows the light or dark appearance of the view that draws it.
    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }
}

public extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color { Color(nsColor: .dynamic(light: light, dark: dark)) }
}

/// The graphite-and-amber colors shared by Ting, Splash Finish and lowkey's Amber preset.
public enum BobukColors {
    public static let panel = NSColor.dynamic(light: 0xF7F8F5, dark: 0x222A2E)
    public static let ink = NSColor.dynamic(light: 0x222A2E, dark: 0xEEF1EC)
    public static let muted = NSColor.dynamic(light: 0x59666C, dark: 0xA4AFB3)
    public static let amber = NSColor.dynamic(light: 0x885500, dark: 0xE7BB74)
    public static let stroke = NSColor.dynamic(light: 0xB3BEC1, dark: 0x526064)
    /// Text on an amber badge or a prominent amber button.
    public static let onAmber = NSColor.dynamic(light: 0xF7F8F5, dark: 0x1D1609)
}

public extension PickerPalette {
    /// The shared amber palette, for windows and panels of apps without their own.
    static var bobukAmber: PickerPalette {
        PickerPalette(surface: BobukColors.panel, text: BobukColors.ink, secondary: BobukColors.muted,
                      accent: BobukColors.amber, border: BobukColors.stroke.withAlphaComponent(0.6),
                      badgeInk: BobukColors.onAmber)
    }

    /// Native system colors.
    static var system: PickerPalette {
        PickerPalette(surface: .windowBackgroundColor, text: .labelColor, secondary: .secondaryLabelColor,
                      accent: .controlAccentColor, border: .separatorColor, badgeInk: .white)
    }

    /// Window chrome in this palette's colors.
    var chromeStyle: ChromeStyle { ChromeStyle(palette: self) }
}

/// The app-wide appearance the user picks in Settings.
public enum AppearanceChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil follows System Settings.
    public var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Sets `NSApp.appearance`, so every window, panel and menu of the app matches.
    @MainActor public func apply() { NSApp.appearance = appearance }

    /// The stored choice under `key`, or `fallback` (Splash Finish keeps dark by default).
    public static func stored(in defaults: UserDefaults = .standard, key: String,
                              fallback: AppearanceChoice = .system) -> AppearanceChoice {
        defaults.string(forKey: key).flatMap(AppearanceChoice.init(rawValue:)) ?? fallback
    }
}
