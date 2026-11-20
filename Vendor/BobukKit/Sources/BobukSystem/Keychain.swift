// One generic-password Keychain item, from HAScS's credential store. The Keychain decides the
// access policy; no broad ACL is installed and the item never synchronizes through iCloud.
import Foundation
import Security

public enum KeychainError: LocalizedError, Equatable {
    case status(OSStatus)
    /// The item exists but does not decode as the expected value.
    case corrupt

    public var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "Keychain: \(message)"
        case .corrupt:
            return "The Keychain item is damaged."
        }
    }
}

public struct KeychainItem: Sendable, Equatable {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    /// The stored bytes, or nil when there is no item.
    public func read() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = result as? Data else { throw KeychainError.corrupt }
        return data
    }

    /// Updates the item, or adds it; one item holds the whole value so updates are atomic.
    public func write(_ data: Data) throws {
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError.status(status) }
        var item = query
        item[kSecValueData as String] = data
        let added = SecItemAdd(item as CFDictionary, nil)
        // Another process may have created the item between update and add.
        if added == errSecDuplicateItem {
            let retry = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard retry == errSecSuccess else { throw KeychainError.status(retry) }
        } else if added != errSecSuccess {
            throw KeychainError.status(added)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    public func readString() throws -> String? { try read().map { String(decoding: $0, as: UTF8.self) } }
    public func write(_ text: String) throws { try write(Data(text.utf8)) }

    public func readCodable<T: Decodable>(_ type: T.Type) throws -> T? {
        guard let data = try read() else { return nil }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw KeychainError.corrupt }
        return value
    }

    public func writeCodable<T: Encodable>(_ value: T) throws { try write(JSONEncoder().encode(value)) }
}
