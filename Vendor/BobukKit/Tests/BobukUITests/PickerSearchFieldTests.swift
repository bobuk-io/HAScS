import AppKit
import SwiftUI
import XCTest
@testable import BobukUI

@MainActor
final class PickerSearchFieldTests: XCTestCase {
    private let palette = PickerPalette(surface: .white, text: .black, secondary: .darkGray,
                                       accent: .systemOrange, border: .gray, badgeInk: .black)

    func testNativeInputReportsTypingAndCancelWithoutRecents() throws {
        _ = NSApplication.shared
        var text = "initial"
        let view = PickerSearchField(text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "Search demo", accessibilityLabel: "Demo search", palette: palette)
        let hosting = NSHostingView(rootView: view.frame(width: 180, height: PickerMetrics.searchFieldHeight))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 60), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(descendants(hosting).first { $0 is NSSearchField } as? NSSearchField)
        XCTAssertEqual(field.stringValue, "initial")
        XCTAssertEqual(field.accessibilityLabel(), "Demo search")
        XCTAssertTrue(field.sendsSearchStringImmediately)
        XCTAssertFalse(field.sendsWholeSearchString)
        XCTAssertEqual(field.maximumRecents, 0)
        XCTAssertNil(field.recentsAutosaveName)
        XCTAssertNil(field.searchMenuTemplate)
        XCTAssertFalse(window.isKeyWindow)

        field.stringValue = "typed query"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(text, "typed query")
        // Native cancel sends the control action after clearing the field.
        field.stringValue = ""
        XCTAssertTrue(field.sendAction(try XCTUnwrap(field.action), to: field.target))
        XCTAssertEqual(text, "")
        XCTAssertEqual(hosting.fittingSize.width, 180, accuracy: 0.5)
        XCTAssertEqual(hosting.fittingSize.height, PickerMetrics.searchFieldHeight, accuracy: 0.5)
    }

    func testProgrammaticUpdatesKeepNativeFieldAndRefreshBinding() async throws {
        var first = "first"
        var second = "second"
        func view(_ binding: Binding<String>) -> some View {
            PickerSearchField(text: binding, placeholder: "Search", accessibilityLabel: "Demo search", palette: palette)
                .frame(width: 200, height: PickerMetrics.searchFieldHeight)
        }
        let hosting = NSHostingView(rootView: view(Binding(get: { first }, set: { first = $0 })))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(descendants(hosting).first { $0 is NSSearchField } as? NSSearchField)
        hosting.rootView = view(Binding(get: { second }, set: { second = $0 }))
        hosting.layoutSubtreeIfNeeded()
        await Task.yield()
        XCTAssertEqual(field.stringValue, "second")
        field.stringValue = "updated"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(first, "first")
        XCTAssertEqual(second, "updated")
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
