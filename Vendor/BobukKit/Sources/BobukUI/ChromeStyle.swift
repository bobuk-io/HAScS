// Colors of a window's chrome: the accent bar, the control strip, its buttons and the separator.
// Apps compute it from their own theme (lowkey from its tint engine, Ting from its palette).
import AppKit

public struct ChromeStyle: Equatable {
    /// The strip and the window background.
    public var panel: NSColor
    /// Hovered and pressed glyphs.
    public var ink: NSColor
    /// Idle glyphs and the optional strip title.
    public var muted: NSColor
    public var accent: NSColor
    /// The line under the strip. Pass `panel` for a strip that flows into the content (lowkey Tint).
    public var separator: NSColor
    /// Hover color of destructive glyphs (close, terminate). nil uses `ink`: on a page-colored
    /// strip a fixed red can match the tint.
    public var destructiveHover: NSColor?
    /// Appearance for strip controls and their tooltips; nil inherits the window's.
    public var appearance: NSAppearance?

    public static let defaultDestructive = NSColor(srgbRed: 0.71, green: 0.33, blue: 0.25, alpha: 1)

    public init(panel: NSColor, ink: NSColor, muted: NSColor, accent: NSColor, separator: NSColor,
                destructiveHover: NSColor? = ChromeStyle.defaultDestructive, appearance: NSAppearance? = nil) {
        self.panel = panel
        self.ink = ink
        self.muted = muted
        self.accent = accent
        self.separator = separator
        self.destructiveHover = destructiveHover
        self.appearance = appearance
    }

    /// Chrome in the colors of a picker palette, so a window matches the app's panels.
    public init(palette: PickerPalette, separator: NSColor? = nil, appearance: NSAppearance? = nil) {
        self.init(panel: palette.surface, ink: palette.text, muted: palette.secondary, accent: palette.accent,
                  separator: separator ?? palette.border, appearance: appearance)
    }

    /// Native system colors, for apps without a palette.
    public static var system: ChromeStyle {
        ChromeStyle(panel: .windowBackgroundColor, ink: .labelColor, muted: .secondaryLabelColor,
                    accent: .controlAccentColor, separator: .separatorColor)
    }
}

/// Geometry of window chrome. Panels keep `PickerMetrics` (3-point accent); windows use a
/// 2-point accent and a 20-point strip, as lowkey's windows always had: 23 points of chrome.
public enum ChromeMetrics {
    public static let accentHeight: CGFloat = 2
    public static let stripHeight: CGFloat = 20
    public static let separatorHeight: CGFloat = 1
    public static let buttonWidth: CGFloat = 26
    public static let stripInset: CGFloat = 4
    public static let buttonSpacing: CGFloat = 1
    public static let glyphSide: CGFloat = 14.4

    /// Accent, strip and separator together: the window height above `body`.
    public static func chromeHeight(accentHeight: CGFloat = accentHeight) -> CGFloat {
        accentHeight + stripHeight + separatorHeight
    }

    /// The window content size for a `body` of `size`.
    public static func windowSize(forBody size: NSSize, accentHeight: CGFloat = accentHeight) -> NSSize {
        NSSize(width: size.width, height: size.height + chromeHeight(accentHeight: accentHeight))
    }
}
