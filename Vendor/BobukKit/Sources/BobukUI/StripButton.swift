// A tiny icon button for a window strip, from lowkey's GlyphButton: hover and press backgrounds,
// red hover for destructive glyphs, click modifiers for the action (⌘-click), first-mouse clicks
// and button accessibility. Window controls go here, never into the window's content.
import AppKit

@MainActor public final class StripButton: NSView {
    public enum Role: Sendable {
        /// Destructive for `.close` and `.terminate`, normal otherwise.
        case automatic, normal, destructive
    }

    public var glyph: Glyph { didSet { needsDisplay = true } }
    /// Tooltip and accessibility label; include the shortcut: "Close · ⌘W".
    public var label: String { didSet { toolTip = label } }
    public var isEnabled = true { didSet { needsDisplay = true } }
    public var role: Role = .automatic { didSet { needsDisplay = true } }
    /// Called on click with the modifiers held (⌘-click), and with `[]` from accessibility.
    public var onPress: ((NSEvent.ModifierFlags) -> Void)?
    /// Explicit colors; nil uses the enclosing `ChromeWindow`'s style, then `.system`.
    public var style: ChromeStyle? { didSet { needsDisplay = true } }

    private var hovering = false
    private var pressed = false
    private var trackingArea: NSTrackingArea?

    public init(glyph: Glyph, label: String, onPress: ((NSEvent.ModifierFlags) -> Void)? = nil) {
        self.glyph = glyph
        self.label = label
        self.onPress = onPress
        super.init(frame: .zero)
        toolTip = label
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var intrinsicContentSize: NSSize { NSSize(width: ChromeMetrics.buttonWidth, height: ChromeMetrics.stripHeight) }

    var resolvedStyle: ChromeStyle { style ?? (window as? ChromeWindow)?.chromeStyle ?? .system }
    var isDestructive: Bool {
        switch role {
        case .automatic: glyph.isDestructive
        case .normal: false
        case .destructive: true
        }
    }

    public override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    public override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    public override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }

    public override func mouseUp(with event: NSEvent) {
        let fire = pressed && isEnabled && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if fire { onPress?(event.modifierFlags) }
    }

    /// The color the glyph is drawn in now.
    func glyphColor() -> NSColor {
        let style = resolvedStyle
        if !isEnabled { return style.muted.withAlphaComponent(0.35) }
        if hovering, isDestructive, let red = style.destructiveHover { return red }
        return hovering ? style.ink : style.muted
    }

    public override func draw(_ dirtyRect: NSRect) {
        let style = resolvedStyle
        if isEnabled && (hovering || pressed) {
            style.ink.withAlphaComponent(pressed ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0), xRadius: 3, yRadius: 3).fill()
        }
        let side = min(bounds.height - 2, ChromeMetrics.glyphSide)
        glyph.draw(in: NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side),
                   color: glyphColor())
    }

    // Accessibility: a plain button.
    public override func isAccessibilityElement() -> Bool { true }
    public override func accessibilityRole() -> NSAccessibility.Role? { .button }
    public override func accessibilityLabel() -> String? { label }
    public override func isAccessibilityEnabled() -> Bool { isEnabled }
    public override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?([])
        return true
    }

    /// Simulates a click, for tests and keyboard handlers.
    public func performPress(modifiers: NSEvent.ModifierFlags = []) {
        guard isEnabled else { return }
        onPress?(modifiers)
    }
}
