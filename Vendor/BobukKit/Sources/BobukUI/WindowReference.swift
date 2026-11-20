// Connects SwiftUI content to its own host window (never `NSApp.keyWindow`, which may belong to
// another window or nothing), and pins AppKit views edge to edge.
import AppKit
import SwiftUI

/// The window that hosts a SwiftUI view. Set by `.windowReference(_:)`.
@MainActor public final class WindowReference {
    public weak var window: NSWindow?
    public init() {}
    /// Closes the host through `performClose`.
    public func close() { window?.performClose(nil) }
}

public extension View {
    /// Fills `reference.window` with the view's host window once it is in one.
    func windowReference(_ reference: WindowReference) -> some View {
        background(WindowReader(reference: reference))
    }
}

private struct WindowReader: NSViewRepresentable {
    let reference: WindowReference
    func makeNSView(context: Context) -> ReaderView { ReaderView(reference: reference) }
    func updateNSView(_ view: ReaderView, context: Context) {
        view.reference = reference
        reference.window = view.window
    }

    final class ReaderView: NSView {
        var reference: WindowReference
        init(reference: WindowReference) {
            self.reference = reference
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference.window = window
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

public extension NSView {
    /// Adds the view to `container` and pins it to all edges (or below `top`).
    @MainActor func pinEdges(to container: NSView, top: NSLayoutYAxisAnchor? = nil) {
        translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: top ?? container.topAnchor),
            leadingAnchor.constraint(equalTo: container.leadingAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
