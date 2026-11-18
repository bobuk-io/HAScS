import AppKit
import SwiftUI
import XCTest
import HAScSCore
import BobukUI
@testable import HAScS

private final class PreviewCredentials: CredentialStorage {
    func read() throws -> Configuration? { nil }
    func save(_ configuration: Configuration) throws { XCTFail("Must not save credentials") }
}

@MainActor final class SharedFooterTests: XCTestCase {
    func testPanelFitsSharedHintsAndKeepsCloseActionWithoutActivatingScenes() throws {
        _ = NSApplication.shared
        let suite = "io.bobuk.HAScS.preview.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = ConfigurationRepository(storage: PreviewCredentials(), defaults: defaults) { throw ConfigurationError.notFound }
        let store = SceneStore(defaults: defaults, configuration: repository)
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: ScenePanelView(store: store,
                activate: { _ in XCTFail("Must not activate scenes") }, close: {}, refresh: {}, settings: {}))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 622, height: 505),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 622, accuracy: 0.5)
            XCTAssertEqual(host.fittingSize.height, 505, accuracy: 0.5)
            XCTAssertFalse(window.isVisible)
            if let directory = ProcessInfo.processInfo.environment["BOBUKKIT_PREVIEW_DIR"] {
                let output = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("hascs-\(dark ? "dark" : "light").png"))
            }
            window.close()
        }
    }
}
