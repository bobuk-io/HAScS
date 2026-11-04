import Foundation
import XCTest
@testable import HAScSCore

final class LocalizationTests: XCTestCase {
    private func languageBundle(_ code: String) throws -> Bundle {
        let path = try XCTUnwrap(L10n.bundle.path(forResource: code, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    private func table(_ code: String) throws -> [String: String] {
        let url = try XCTUnwrap(try languageBundle(code).url(forResource: "Localizable", withExtension: "strings"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    func testAllLanguagesContainTheSameStringsAndPlaceholders() throws {
        let english = try table("en")
        let pattern = try NSRegularExpression(pattern: "%(@|lld)")
        func placeholders(_ value: String) -> [String] {
            pattern.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        for code in L10n.supportedLanguages {
            let translations = try table(code)
            XCTAssertEqual(Set(translations.keys), Set(english.keys), "Missing or extra keys for \(code)")
            for (key, value) in translations {
                XCTAssertFalse(value.isEmpty, "Empty translation: \(code) / \(key)")
                XCTAssertEqual(placeholders(key), placeholders(value), "Bad placeholders: \(code) / \(key)")
            }
        }
    }

    func testTranslatedTitlesAndErrors() throws {
        for (code, title) in [("en", "Home scenes"), ("uk", "Сцени дому"), ("ru", "Сцены дома")] {
            let bundle = try languageBundle(code)
            XCTAssertEqual(String(localized: "Home scenes", bundle: bundle, locale: Locale(identifier: code)), title)
            let unauthorized = String(localized: "Home Assistant rejected the token. Check the access token in Settings.",
                                      bundle: bundle, locale: Locale(identifier: code))
            XCTAssertFalse(unauthorized.contains(".env"))
            XCTAssertFalse(unauthorized.isEmpty)
        }
    }

    func testSceneCountPluralForms() throws {
        let expected: [String: [String]] = [
            "en": ["1 scene", "2 scenes", "5 scenes", "11 scenes", "21 scenes"],
            "uk": ["1 сцена", "2 сцени", "5 сцен", "11 сцен", "21 сцена"],
            "ru": ["1 сцена", "2 сцены", "5 сцен", "11 сцен", "21 сцена"],
        ]
        for code in L10n.supportedLanguages {
            let bundle = try languageBundle(code)
            let counts = [1, 2, 5, 11, 21]
            let rendered = counts.map { count in
                String(localized: "\(count) scenes", bundle: bundle, locale: Locale(identifier: code))
            }
            XCTAssertEqual(rendered, expected[code], "Incorrect plural rules for \(code)")
        }
    }

    func testLanguagePreferenceDoesNotTouchCredentials() throws {
        let suite = "io.bobuk.HAScS.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "credentials.migrated.v1")
        InterfaceLanguage.uk.save(in: defaults)
        XCTAssertEqual(InterfaceLanguage.selected(in: defaults), .uk)
        XCTAssertEqual(defaults.stringArray(forKey: "AppleLanguages"), ["uk"])
        InterfaceLanguage.system.save(in: defaults)
        XCTAssertEqual(InterfaceLanguage.selected(in: defaults), .system)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        XCTAssertTrue(defaults.bool(forKey: "credentials.migrated.v1"))
    }
}
