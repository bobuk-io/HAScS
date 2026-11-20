// The running app's bundle, executable and version, found without SwiftPM's `Bundle.module`
// (which embeds the builder's absolute build path) and without trusting `Bundle.main` when the
// executable was started through a symlink (a command-line companion in /usr/local/bin).
import Darwin
import Foundation

public enum AppBundle {
    /// The running executable, symlinks resolved.
    public static let executableURL: URL = {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return URL(fileURLWithPath: CommandLine.arguments.first ?? "/").resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL.resolvingSymlinksInPath()
    }()

    /// `X.app` for `X.app/Contents/MacOS/<executable>`; nil for `swift run` and test hosts.
    public static func applicationURL(for executable: URL = executableURL) -> URL? {
        let directory = executable.deletingLastPathComponent()
        let contents = directory.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard directory.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else { return nil }
        return app
    }

    /// The enclosing `.app` of the running executable.
    public static var applicationURL: URL? { applicationURL(for: executableURL) }

    /// True when running from a packaged `.app` (not `swift run` or `swift test`).
    public static var isPackaged: Bool { applicationURL != nil }

    /// Info.plist of the enclosing app; empty outside an app bundle.
    public static var info: [String: Any] {
        applicationURL.flatMap(Bundle.init(url:))?.infoDictionary ?? [:]
    }

    /// `CFBundleShortVersionString`, or `0.0.0-dev` outside an app bundle.
    public static var version: String { info["CFBundleShortVersionString"] as? String ?? "0.0.0-dev" }

    /// `CFBundleVersion`, or `0` outside an app bundle.
    public static var build: String { info["CFBundleVersion"] as? String ?? "0" }

    /// True when Info.plist has a non-empty `SUFeedURL` and `SUPublicEDKey`: a Sparkle release copy.
    public static func hasSparkleFeed(info: [String: Any] = info) -> Bool {
        (info["SUFeedURL"] as? String)?.isEmpty == false && (info["SUPublicEDKey"] as? String)?.isEmpty == false
    }

    /// A SwiftPM resource bundle such as `HAScS_HAScSCore.bundle`: inside `Contents/Resources` of
    /// the app, next to the executable for `swift run`, or next to the loaded `.xctest` bundle
    /// under `swift test` (where the executable is Xcode's `xctest` runner).
    public static func resourceBundle(named name: String, executable: URL = executableURL) -> Bundle? {
        var roots: [URL] = []
        if let app = applicationURL(for: executable) {
            roots.append(app.appendingPathComponent("Contents/Resources", isDirectory: true))
        } else {
            roots.append(executable.deletingLastPathComponent())
            roots += Bundle.allBundles.filter { $0.bundleURL.pathExtension == "xctest" }
                .map { $0.bundleURL.deletingLastPathComponent() }
        }
        for root in roots {
            if let bundle = Bundle(url: root.appendingPathComponent(name, isDirectory: true)) { return bundle }
        }
        return nil
    }

    /// True for a Finder/LaunchServices launch argument such as `-psn_0_12345` (older macOS).
    public static func isProcessSerialNumber(_ argument: String) -> Bool { argument.hasPrefix("-psn_") }
}
