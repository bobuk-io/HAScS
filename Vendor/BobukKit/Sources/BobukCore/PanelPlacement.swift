// Where a panel appears on a screen. Pure geometry in AppKit screen coordinates (y grows up),
// so it is tested without screens. `BobukUI.Screens` supplies the screen under the pointer.
import CoreGraphics
import Foundation

/// The vertical anchor of a panel inside a screen's visible area.
public enum PanelAnchor: Equatable, Sendable {
    /// Centered; a positive offset moves it up. Leader menu and HAScS: 0; Splash Finish: -55.
    case center(offsetUp: CGFloat = 0)
    /// Top edge `fraction` of the height below the top, at least `minimum` points.
    /// launcha, Clipbawd and micro-apps: `.upper()`. lowkey's address prompt: `.upper(fraction: 0.28, minimum: 0)`.
    case upper(fraction: CGFloat = 0.16, minimum: CGFloat = 40)
    /// Top edge `inset` points below the top of the visible area (Ting's toast: 80).
    case top(inset: CGFloat)
}

public enum PanelPlacement {
    public struct Result: Equatable, Sendable {
        public var frame: CGRect
        /// Visible area of the screen that hosts the panel; sizes a scrolling list.
        public var area: CGRect
        public init(frame: CGRect, area: CGRect) { self.frame = frame; self.area = area }
    }

    /// A frame of `size`, horizontally centered in `area`, at `anchor`, kept `margin` points inside.
    public static func frame(size: CGSize, in area: CGRect, anchor: PanelAnchor, margin: CGFloat = 16) -> CGRect {
        let x = area.midX - size.width / 2
        let y: CGFloat
        switch anchor {
        case .center(let offset): y = area.midY - size.height / 2 + offset
        case .upper(let fraction, let minimum): y = area.maxY - max(minimum, area.height * fraction) - size.height
        case .top(let inset): y = area.maxY - inset - size.height
        }
        let clampedY = clamp(y, area.minY + margin, area.maxY - size.height - margin)
        return CGRect(x: x, y: clampedY, width: size.width, height: size.height)
    }

    /// The top edge of `anchor` in `area`, for panels that size their height from the top down
    /// (launcha: `height = min(640, top - area.minY - 20)`). `.center` has no fixed top: midY.
    public static func top(in area: CGRect, anchor: PanelAnchor) -> CGFloat {
        switch anchor {
        case .center(let offset): area.midY + offset
        case .upper(let fraction, let minimum): area.maxY - max(minimum, area.height * fraction)
        case .top(let inset): area.maxY - inset
        }
    }

    /// The remembered top-left corner while it still lies on a connected screen, clamped so the
    /// whole panel stays visible; otherwise `anchor` on the active screen. From Splash Finish,
    /// whose inbox the user can drag.
    public static func place(size: CGSize, remembered topLeft: CGPoint?, screens: [CGRect], active: CGRect,
                             anchor: PanelAnchor = .center(offsetUp: -55), margin: CGFloat = 16) -> Result {
        if let topLeft, let area = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(topLeft) }) {
            let x = clamp(topLeft.x, area.minX, area.maxX - size.width)
            let top = clamp(topLeft.y, area.minY + size.height, area.maxY)
            return Result(frame: CGRect(x: x, y: top - size.height, width: size.width, height: size.height), area: area)
        }
        return Result(frame: frame(size: size, in: active, anchor: anchor, margin: margin), area: active)
    }

    /// `frame` with a new height and the same top edge, kept inside `area` when given.
    public static func resize(_ frame: CGRect, toHeight height: CGFloat, keepingTopIn area: CGRect? = nil,
                              margin: CGFloat = 16) -> CGRect {
        var result = frame
        result.origin.y = frame.maxY - height
        result.size.height = height
        if let area { result.origin.y = clamp(result.origin.y, area.minY + margin, area.maxY - height - margin) }
        return result
    }

    /// Centered on `parent`, its top edge `inset` points below the parent's top (lowkey's ⌘L prompt).
    public static func over(parent: CGRect, size: CGSize, inset: CGFloat) -> CGRect {
        CGRect(x: parent.midX - size.width / 2, y: parent.maxY - inset - size.height, width: size.width, height: size.height)
    }

    /// The lower bound wins when the panel is taller or wider than the screen.
    static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        max(lower, min(upper, value))
    }
}
