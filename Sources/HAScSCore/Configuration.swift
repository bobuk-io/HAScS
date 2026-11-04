import Foundation

public enum ConfigurationError: LocalizedError, Equatable {
    case notFound
    case missingValues
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .notFound: L10n.string("Configure your Home Assistant connection in Settings.")
        case .missingValues: L10n.string("Enter the Home Assistant URL and a non-empty token.")
        case .invalidURL: L10n.string("Enter a valid http or https URL without a username or password.")
        }
    }
}

public struct Configuration: Sendable, Equatable {
    public let baseURL: URL
    public let token: String

    public init(baseURL: URL, token: String) throws {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw ConfigurationError.invalidURL
        }
        guard !token.isEmpty, !token.contains("\n"), !token.contains("\r") else {
            throw ConfigurationError.missingValues
        }
        self.baseURL = baseURL
        self.token = token
    }

    public static func parse(_ contents: String) throws -> Configuration {
        var values: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("export ") { trimmed.removeFirst(7) }
            guard !trimmed.hasPrefix("#"), let equal = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equal].trimmingCharacters(in: .whitespaces)
            guard key == "HA_URL" || key == "HA_TOKEN" else { continue }
            var value = String(trimmed[trimmed.index(after: equal)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = value
        }
        guard let urlString = values["HA_URL"], !urlString.isEmpty,
              let token = values["HA_TOKEN"], !token.isEmpty else {
            throw ConfigurationError.missingValues
        }
        guard let url = URL(string: urlString) else { throw ConfigurationError.invalidURL }
        return try Configuration(baseURL: url, token: token)
    }

    /// Used only for a one-time migration from earlier versions; never as a runtime fallback.
    public static func loadLegacy(environment: [String: String] = ProcessInfo.processInfo.environment,
                            bundleURL: URL = Bundle.main.bundleURL,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Configuration {
        let candidates: [URL]
        if let explicit = environment["HASCS_ENV_FILE"], !explicit.isEmpty {
            candidates = [URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)]
        } else {
            candidates = [
                home.appendingPathComponent(".config/HAScS/.env"),
                // Development bundle: project/build/HAScS.app -> project/.env.
                bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env"),
            ]
        }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ConfigurationError.notFound
        }
        do { return try parse(String(contentsOf: path, encoding: .utf8)) }
        catch let error as ConfigurationError { throw error }
        catch { throw ConfigurationError.notFound }
    }
}
