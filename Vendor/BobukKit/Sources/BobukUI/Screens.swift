// The screen a panel belongs on and the AppKit side of `PanelPlacement`.
import AppKit
import BobukCore

@MainActor public enum Screens {
    /// The screen under the pointer (where the user is looking), else the main screen.
    /// `NSMouseInRect` treats screen edges correctly, unlike `frame.contains`.
    public static var underPointer: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Visible frames of all connected screens, for `PanelPlacement.place(remembered:)`.
    public static var visibleFrames: [CGRect] { NSScreen.screens.map(\.visibleFrame) }
}

public extension NSWindow {
    /// Sets the frame to `size` at `anchor` on `screen` (nil: the pointer's). Returns the
    /// visible area used, to size scrolling lists; nil without screens.
    @MainActor @discardableResult
    func place(size: NSSize, anchor: PanelAnchor, on screen: NSScreen? = nil,
               margin: CGFloat = 16, display: Bool = false) -> CGRect? {
        guard let area = (screen ?? Screens.underPointer)?.visibleFrame else { return nil }
        setFrame(PanelPlacement.frame(size: size, in: area, anchor: anchor, margin: margin), display: display)
        return area
    }

    /// Resizes to the fitting height of `view`, keeping the top edge, and refreshes the shadow.
    @MainActor func fitHeight(to view: NSView, width: CGFloat? = nil, keepingTopIn area: CGRect? = nil) {
        view.layoutSubtreeIfNeeded()
        let height = view.fittingSize.height
        var frame = PanelPlacement.resize(self.frame, toHeight: height, keepingTopIn: area)
        if let width { frame.size.width = width }
        setFrame(frame, display: true)
        invalidateShadow()
    }
}
