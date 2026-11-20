// Helpers for tests of bobuk-io apps. Independent of the test framework (XCTest or Swift Testing):
// nothing here asserts. Every helper works in a fresh temporary folder, never in real data.
import BobukCore
import Foundation

/// A fresh folder under the temporary directory, removed by `remove()` or on deinit.
public final class TemporaryDirectory: @unchecked Sendable {
    public let url: URL

    public init(prefix: String = "bobukkit-test") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { remove() }

    public func remove() { try? FileManager.default.removeItem(at: url) }

    /// `url/<path>`, with parent folders created.
    public func file(_ path: String) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return file
    }

    /// Writes an executable `/bin/sh` script at `path` and returns it.
    @discardableResult
    public func executable(_ path: String, script: String) throws -> URL {
        let file = try file(path)
        try ("#!/bin/sh\n" + script + "\n").write(to: file, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    /// A minimal `X.app` with `Contents/Info.plist` and an executable `Contents/MacOS/<executable>`.
    @discardableResult
    public func appBundle(_ path: String, executable: String, info: [String: Any] = [:]) throws -> URL {
        let app = url.appendingPathComponent(path)
        try self.executable("\(path)/Contents/MacOS/\(executable)", script: "exit 0")
        var plist: [String: Any] = ["CFBundleExecutable": executable, "CFBundlePackageType": "APPL"]
        plist.merge(info) { $1 }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    /// An environment where the app's override variable points into this folder.
    public func isolatedPaths(supportFolder: String, overrideVariable: String,
                              configFileName: String = "config.json") -> AppPaths {
        AppPaths(supportFolder: supportFolder, configFileName: configFileName, overrideVariable: overrideVariable,
                 environment: [overrideVariable: url.appendingPathComponent(configFileName).path], home: url)
    }
}

public enum IsolatedDefaults {
    /// A fresh `UserDefaults` suite; remove it with `remove(_:)`.
    public static func make(_ name: String = "bobukkit-test-\(UUID().uuidString)") -> (UserDefaults, String) {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    public static func remove(_ name: String) {
        UserDefaults().removePersistentDomain(forName: name)
    }
}

public enum VersionFile {
    /// `MARKETING_VERSION` from a `version.env` such as `<repo>/version.env`.
    public static func marketingVersion(in versionEnv: URL) -> String? {
        guard let text = try? String(contentsOf: versionEnv, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("MARKETING_VERSION=") {
            return String(line.dropFirst("MARKETING_VERSION=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        return nil
    }

    /// The repository root of a test file: walks up from `#filePath` to the folder with `Package.swift`.
    public static func packageRoot(from file: String) -> URL? {
        var url = URL(fileURLWithPath: file).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
