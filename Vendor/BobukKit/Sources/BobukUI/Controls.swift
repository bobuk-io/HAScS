// Small SwiftUI controls repeated across apps: the quiet bordered button (Splash Finish "Snooze",
// Ting dialogs), the mono tracked label and a glyph button for row actions (dismiss, remove).
import SwiftUI

/// Small bordered button. `prominent` fills it with the accent.
public struct QuietButtonStyle: ButtonStyle {
    private let palette: PickerPalette
    private let prominent: Bool
    private let height: CGFloat
    private let prominentFill: NSColor?

    public init(palette: PickerPalette, prominent: Bool = false, height: CGFloat = 30, prominentFill: NSColor? = nil) {
        self.palette = palette
        self.prominent = prominent
        self.height = height
        self.prominentFill = prominentFill
    }

    public func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration, palette: palette, prominent: prominent, height: height,
                    prominentFill: prominentFill)
    }

    private struct QuietButton: View {
        let configuration: Configuration
        let palette: PickerPalette
        let prominent: Bool
        let height: CGFloat
        let prominentFill: NSColor?
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let ink = Color(nsColor: palette.text)
            let fill = Color(nsColor: prominentFill ?? palette.accent)
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 13)
                .frame(height: height)
                .foregroundStyle(prominent ? Color(nsColor: palette.badgeInk) : ink)
                .background(prominent ? fill.opacity(configuration.isPressed ? 0.8 : 1)
                                      : ink.opacity(configuration.isPressed ? 0.14 : 0.05),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(ink.opacity(prominent ? 0 : contrast == .increased ? 0.35 : 0.1)))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// Mono, tracked, upper-case label: "TING", "W / WEB", "04".
public struct MonoLabel: View {
    private let text: String
    private let size: CGFloat
    private let weight: Font.Weight
    private let tracking: CGFloat

    public init(_ text: String, size: CGFloat = 10, weight: Font.Weight = .semibold, tracking: CGFloat = 1.5) {
        self.text = text
        self.size = size
        self.weight = weight
        self.tracking = tracking
    }

    public var body: some View {
        Text(text.uppercased()).font(.system(size: size, weight: weight, design: .monospaced)).tracking(tracking)
    }
}

/// A square glyph button for an action inside content: dismiss a card, remove a history row.
/// Window controls are `StripButton`s in a `ChromeWindow` strip, not this.
public struct GlyphButton: View {
    private let glyph: Glyph
    private let label: String
    private let palette: PickerPalette
    private let width: CGFloat
    private let height: CGFloat
    private let glyphSize: CGFloat
    private let hoverFill: Bool
    private let help: String?
    private let action: () -> Void
    @State private var hovering = false

    /// A `size`×`size` button with a hover fill.
    public init(_ glyph: Glyph, label: String, help: String? = nil, palette: PickerPalette, size: CGFloat = 22,
                action: @escaping () -> Void) {
        self.init(glyph, label: label, help: help, palette: palette, width: size, height: size, glyphSize: size * 0.5,
                  action: action)
    }

    /// A `width`×`height` hit area (a narrow row column) with a `glyphSize` glyph; `hoverFill: false`
    /// only brightens the glyph on hover.
    /// `help` is the tooltip when it differs from the spoken `label`.
    public init(_ glyph: Glyph, label: String, help: String? = nil, palette: PickerPalette, width: CGFloat, height: CGFloat,
                glyphSize: CGFloat, hoverFill: Bool = true, action: @escaping () -> Void) {
        self.help = help
        self.glyph = glyph
        self.label = label
        self.palette = palette
        self.width = width
        self.height = height
        self.glyphSize = glyphSize
        self.hoverFill = hoverFill
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            GlyphImage(glyph, size: glyphSize)
                .foregroundStyle(Color(nsColor: hovering ? palette.text : palette.secondary))
                .frame(width: width, height: height)
                .background(Color(nsColor: palette.text).opacity(hoverFill && hovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}
