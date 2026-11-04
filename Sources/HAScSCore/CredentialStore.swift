import Foundation
import Security

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

/// One generic-password item contains both values, so updates are atomic.
/// The Keychain decides the item's access policy; no broad access ACL is installed.
public struct KeychainCredentialStore: CredentialStorage {
    private let service: String
    private let account = "home-assistant-connection"

    public init(service: String = "io.bobuk.HAScS.credentials.v1") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    public func read() throws -> Configuration? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
        guard let data = result as? Data,
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data),
              let url = URL(string: stored.url),
              let configuration = try? Configuration(baseURL: url, token: stored.token) else {
            throw CredentialError.corrupt
        }
        return configuration
    }

    public func save(_ configuration: Configuration) throws {
        let data = try JSONEncoder().encode(StoredCredentials(url: configuration.baseURL.absoluteString, token: configuration.token))
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychain(status) }
        var item = query
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        // Another process may have created the item between update and add.
        if addStatus == errSecDuplicateItem {
            let retry = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard retry == errSecSuccess else { throw CredentialError.keychain(retry) }
        } else if addStatus != errSecSuccess {
            throw CredentialError.keychain(addStatus)
        }
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
