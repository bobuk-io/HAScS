// One Codable value in one JSON file, with an explicit policy for a file that cannot be read.
// Ting, lowkey and Splash Finish each wrote this with a different, implicit policy.
import Foundation

public enum JSONFileStoreError: LocalizedError, Equatable {
    /// The file exists but does not decode. Writes are refused under `.refuseWrites` so the
    /// user's file is never replaced by defaults.
    case unreadable(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path, let reason): "\(path) cannot be read: \(reason)"
        }
    }
}

/// Stores one `Value` as pretty, key-sorted JSON written with `SafeFile.write`.
public struct JSONFileStore<Value: Codable>: Sendable where Value: Sendable {
    /// What to do with a file that exists but does not decode.
    public enum CorruptPolicy: Sendable, Equatable {
        /// Report it; `save` refuses to overwrite it until the user fixes or removes it.
        case refuseWrites
        /// Move it aside to `<name>.corrupt-<timestamp>` and start from the default value.
        case backUp
    }

    public enum Loaded: Sendable {
        /// No file yet: the default value.
        case missing(Value)
        case loaded(Value)
        /// `.backUp` moved an unreadable file aside to `backup`; the value is the default.
        case recovered(Value, backup: URL)
        /// `.refuseWrites`: the file stays and the error says why it cannot be read.
        case unreadable(JSONFileStoreError)

        public var value: Value? {
            switch self {
            case .missing(let value), .loaded(let value), .recovered(let value, _): value
            case .unreadable: nil
            }
        }
    }

    public let url: URL
    public let policy: CorruptPolicy
    private let makeDefault: @Sendable () -> Value

    public init(url: URL, policy: CorruptPolicy = .refuseWrites, default makeDefault: @escaping @Sendable () -> Value) {
        self.url = url
        self.policy = policy
        self.makeDefault = makeDefault
    }

    public func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing(makeDefault()) }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try JSONDecoder().decode(Value.self, from: data))
        } catch {
            let problem = JSONFileStoreError.unreadable(path: url.path, reason: error.localizedDescription)
            switch policy {
            case .refuseWrites:
                return .unreadable(problem)
            case .backUp:
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
                guard (try? FileManager.default.moveItem(at: url, to: backup)) != nil else { return .unreadable(problem) }
                return .recovered(makeDefault(), backup: backup)
            }
        }
    }

    /// Writes `value`. Under `.refuseWrites` an existing unreadable file is never replaced.
    public func save(_ value: Value) throws {
        if policy == .refuseWrites, case .unreadable(let problem) = load() { throw problem }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try SafeFile.write(encoder.encode(value), to: url)
    }
}
