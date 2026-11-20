import BobukCore
import Foundation

/// Resolve resources relative to the running app, `swift run` or the loaded XCTest bundle only
/// (BobukKit's `AppBundle`). Do not use Bundle.module: SwiftPM's generated accessor embeds the
/// builder's absolute checkout path, even when that fallback is never used at runtime.
public enum L10n {
    public static let supportedLanguages = ["en", "uk", "ru"]
    public static let bundle: Bundle = {
        guard let bundle = AppBundle.resourceBundle(named: "HAScS_HAScSCore.bundle") else {
            fatalError("HAScS localization resources are missing from the application.")
        }
        return bundle
    }()

    public static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: bundle)
    }

    public static func sceneCount(_ count: Int) -> String {
        String(localized: "\(count) scenes", bundle: bundle)
    }

    public static func keychainError(_ status: Int32) -> String {
        String(localized: "Unable to access Keychain (code \(Int(status))). Make sure it is unlocked and HAScS is allowed access.", bundle: bundle)
    }

    public static func httpError(_ status: Int) -> String {
        String(localized: "Home Assistant returned HTTP error \(status).", bundle: bundle)
    }

    public static func uncertainActivation(_ error: String) -> String {
        String(localized: "\(error) The scene may have run. Check your devices before trying again.", bundle: bundle)
    }
}

public enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, en, uk, ru
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .system: L10n.string("System language")
        case .en: "English"
        case .uk: "Українська"
        case .ru: "Русский"
        }
    }
    public static func selected(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "system") ?? .system
    }
    public func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "interfaceLanguage")
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
