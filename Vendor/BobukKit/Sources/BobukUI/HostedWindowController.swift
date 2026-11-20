// One app window that is created on demand, remembers its frame, activates the accessory app
// when shown and releases its content when closed (so shortcut recorders, timers and secure
// fields do not live on). Settings, Welcome, permission and update windows of every app.
import AppKit
import SwiftUI
import BobukSystem

@MainActor open class HostedWindowController: NSObject, NSWindowDelegate, Sendable {
    public typealias WindowFactory = @MainActor () -> NSWindow
    public typealias ContentFactory = @MainActor () -> NSView

    public private(set) var window: NSWindow?
    public let frameName: String?
    /// Drop the window and its content on close; the next `show` builds them again.
    public var releasesContentOnClose: Bool
    /// After the window closed.
    public var onClose: (() -> Void)?
    /// Size the window to the content's fitting size when it is built (fixed dialogs).
    public var sizesToFitContent = false
    private let makeWindow: WindowFactory
    private let makeContent: ContentFactory

    /// - Parameter window: usually a `ChromeWindow`; its content goes into `body`.
    public init(frameName: String? = nil, releasesContentOnClose: Bool = true,
                window: @escaping WindowFactory, content: @escaping ContentFactory) {
        self.frameName = frameName
        self.releasesContentOnClose = releasesContentOnClose
        makeWindow = window
        makeContent = content
        super.init()
    }

    /// A controller for a SwiftUI root view.
    public convenience init<Content: View>(frameName: String? = nil, releasesContentOnClose: Bool = true,
                                           window: @escaping WindowFactory,
                                           @ViewBuilder rootView: @escaping @MainActor () -> Content) {
        self.init(frameName: frameName, releasesContentOnClose: releasesContentOnClose, window: window,
                  content: { ChromeWindow.hosting(rootView()) })
    }

    public var isOpen: Bool { window?.isVisible == true }

    /// Builds the window when needed and brings it to the front. `activate: false` orders it
    /// behind other windows without activating the app (tests, background restore).
    public func show(activate: Bool = true) {
        let window = prepare()
        if activate {
            AppActivation.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderBack(nil)
        }
    }

    /// Closes through `performClose`, so `windowShouldClose` and `windowWillClose` run.
    public func close() { window?.performClose(nil) }

    /// Builds the window and its content without showing it (tests, prewarming); returns the
    /// existing window when there is one.
    @discardableResult
    public func prepare() -> NSWindow {
        if let window { return window }
        let window = makeWindow()
        window.delegate = self
        window.isReleasedWhenClosed = false
        let content = makeContent()
        if let chrome = window as? ChromeWindow { chrome.setContent(content) } else { window.contentView = content }
        if sizesToFitContent {
            window.contentView?.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            if let chrome = window as? ChromeWindow {
                window.setContentSize(chrome.contentSize(forBody: fitting))
            } else {
                window.setContentSize(fitting)
            }
        }
        if let frameName {
            if !window.setFrameUsingName(frameName) { window.center() }
            window.setFrameAutosaveName(frameName)
        } else {
            window.center()
        }
        self.window = window
        return window
    }

    open func windowShouldClose(_ sender: NSWindow) -> Bool { true }

    open func windowWillClose(_ notification: Notification) {
        if releasesContentOnClose, let window {
            if let chrome = window as? ChromeWindow { chrome.removeContent() } else { window.contentView = nil }
            window.delegate = nil
            self.window = nil
        }
        onClose?()
    }
}
