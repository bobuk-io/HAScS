import BobukSystem
import Foundation

public enum CredentialError: LocalizedError, Equatable {
    case keychain(OSStatus)
    case corrupt

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            L10n.keychainError(status)
        case .corrupt:
            L10n.string("The Keychain settings are damaged. Enter the URL and token again in Settings.")
        }
    }
}

public protocol CredentialStorage {
    func read() throws -> Configuration?
    func save(_ configuration: Configuration) throws
}

/// One generic-password item (BobukSystem's `KeychainItem`) contains both values as JSON
/// (`{"url":…,"token":…}`), so updates are atomic. The Keychain decides the item's access
/// policy; no broad access ACL is installed and the item never synchronizes.
public struct KeychainCredentialStore: CredentialStorage {
    private let item: KeychainItem

    public init(service: String = "io.bobuk.HAScS.credentials.v1") {
        item = KeychainItem(service: service, account: "home-assistant-connection")
    }

    public func read() throws -> Configuration? {
        guard let stored = try mapped({ try item.readCodable(StoredCredentials.self) }) else { return nil }
        guard let url = URL(string: stored.url),
              let configuration = try? Configuration(baseURL: url, token: stored.token) else {
            throw CredentialError.corrupt
        }
        return configuration
    }

    public func save(_ configuration: Configuration) throws {
        let stored = StoredCredentials(url: configuration.baseURL.absoluteString, token: configuration.token)
        try mapped { try item.writeCodable(stored) }
    }

    /// Keychain failures keep HAScS's localized messages.
    private func mapped<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch KeychainError.status(let status) { throw CredentialError.keychain(status) }
        catch KeychainError.corrupt { throw CredentialError.corrupt }
    }

    private struct StoredCredentials: Codable {
        let url: String
        let token: String
    }
}

/// Import legacy credentials only when there is no item and no previous migration.
/// Failure to access Keychain never falls back to plaintext credentials.
public final class ConfigurationRepository {
    private let storage: any CredentialStorage
    private let defaults: UserDefaults
    private let legacyStorage: (any CredentialStorage)?
    private let legacyDefaults: UserDefaults?
    private let legacyLoader: () throws -> Configuration
    private let migrationKey = "credentials.migrated.v1"

    public init(storage: any CredentialStorage = KeychainCredentialStore(),
                defaults: UserDefaults = .standard,
                legacyStorage: (any CredentialStorage)? = nil,
                legacyDefaults: UserDefaults? = nil,
                legacyLoader: @escaping () throws -> Configuration = { try Configuration.loadLegacy() }) {
        self.storage = storage
        self.defaults = defaults
        self.legacyStorage = legacyStorage
        self.legacyDefaults = legacyDefaults
        self.legacyLoader = legacyLoader
    }

    public func load() throws -> Configuration {
        if let configuration = try storage.read() {
            defaults.set(true, forKey: migrationKey)
            return configuration
        }
        guard !defaults.bool(forKey: migrationKey) else { throw ConfigurationError.notFound }
        // Prefer the earlier Keychain item. A denied or locked Keychain is an
        // error, not permission to use an older plaintext token from .env.
        let legacy: Configuration
        if let old = try legacyStorage?.read() {
            legacy = old
        } else {
            guard legacyDefaults?.bool(forKey: migrationKey) != true else { throw ConfigurationError.notFound }
            legacy = try legacyLoader()
        }
        try storage.save(legacy)
        defaults.set(true, forKey: migrationKey)
        return legacy
    }

    public func save(_ configuration: Configuration) throws {
        try storage.save(configuration)
        defaults.set(true, forKey: migrationKey)
    }
}
