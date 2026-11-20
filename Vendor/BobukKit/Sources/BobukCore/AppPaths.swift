// Where an app keeps its files, with one environment variable that moves all of them for tests
// and screenshots. Every bobuk-io app had its own copy of this rule.
import Foundation

/// File locations of one app.
///
/// - Without the override: the configuration lives in `~/.config/<configFolder>/` when
///   `configFolder` is set (Ting's `~/.config/ting/config.json`), otherwise in Application Support;
///   other files live in `~/Library/Application Support/<supportFolder>/`.
/// - With the override (`TING_CONFIG=/tmp/x/config.json`): the configuration is that file and
///   every other file is its sibling (`/tmp/x/history.json`), so a test never touches real data.
public struct AppPaths: Sendable, Equatable {
    public var supportFolder: String
    public var configFolder: String?
    public var configFileName: String
    public var overrideVariable: String?
    /// A variable that names a whole folder instead of the config file (`SPLASH_FINISH_HOME`):
    /// every file, the configuration included, then lives in that folder.
    public var folderOverrideVariable: String?
    public var environment: [String: String]
    public var home: URL

    public init(supportFolder: String, configFolder: String? = nil, configFileName: String = "config.json",
                overrideVariable: String? = nil, folderOverrideVariable: String? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.supportFolder = supportFolder
        self.configFolder = configFolder
        self.configFileName = configFileName
        self.overrideVariable = overrideVariable
        self.folderOverrideVariable = folderOverrideVariable
        self.environment = environment
        self.home = home
    }

    /// The override file, when a variable is set to a non-empty path. A folder override means
    /// `<folder>/<configFileName>`.
    public var override: URL? {
        // Not standardized: the path stays as the user wrote it (after `~`), as the apps always kept it.
        if let name = overrideVariable, let value = environment[name], !value.isEmpty {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        }
        if let name = folderOverrideVariable, let value = environment[name], !value.isEmpty {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL.appendingPathComponent(configFileName)
        }
        return nil
    }

    /// True when the override variable isolates this process.
    public var isIsolated: Bool { override != nil }

    /// `~/Library/Application Support/<supportFolder>`, or the override's folder.
    public var support: URL {
        if let override { return override.deletingLastPathComponent() }
        return home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(supportFolder, isDirectory: true)
    }

    /// The configuration file.
    public var config: URL {
        if let override { return override }
        if let configFolder {
            return home.appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent(configFolder, isDirectory: true).appendingPathComponent(configFileName)
        }
        return support.appendingPathComponent(configFileName)
    }

    /// Another data file: a sibling of the override, otherwise in Application Support.
    public func file(_ name: String) -> URL { support.appendingPathComponent(name) }

    /// A data file: `<config>.<name>` next to an overridden configuration (Ting's
    /// `$TING_CONFIG.launcha-history.json`), otherwise `<support>/<name>`.
    public func dataFile(_ name: String) -> URL {
        if let override { return override.deletingLastPathComponent().appendingPathComponent("\(override.lastPathComponent).\(name)") }
        return file(name)
    }

    /// A file named after the configuration, such as `<config>.history.json` (lowkey's history).
    public func companion(_ suffix: String) -> URL {
        if let override { return override.deletingLastPathComponent().appendingPathComponent(override.lastPathComponent + suffix) }
        return file(configFileName + suffix)
    }
}
