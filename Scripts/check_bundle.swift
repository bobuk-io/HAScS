#!/usr/bin/env swift
import Foundation

// Read-only release validation. This never launches HAScS or accesses HA/Keychain.
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("Bundle check failed: \(message)\n", stderr); exit(1) }
}
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift Scripts/check_bundle.swift /path/to/HAScS.app\n", stderr)
    exit(1)
}
let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard let app = Bundle(url: appURL),
      let resources = app.resourceURL,
      let module = Bundle(url: resources.appendingPathComponent("HAScS_HAScSCore.bundle")) else {
    fputs("App or embedded localization bundle missing\n", stderr)
    exit(1)
}
require(app.bundleIdentifier == "io.bobuk.HAScS", "unexpected bundle identifier")
require(app.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "Icon", "unexpected app icon reference")
guard let icon = try? Data(contentsOf: resources.appendingPathComponent("Icon.icns")) else {
    fputs("Bundle check failed: app icon is missing\n", stderr)
    exit(1)
}
require(icon.count > 8 && icon.prefix(4) == Data("icns".utf8), "invalid ICNS icon")
require(Set(app.localizations) == Set(["en", "uk", "ru"]), "unexpected app localizations")
require(app.developmentLocalization == "en", "English fallback missing")
let expected = ["en": "Home scenes", "uk": "Сцени дому", "ru": "Сцены дома"]
for language in ["en", "uk", "ru"] {
    guard let path = module.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else {
        fputs("Missing language: \(language)\n", stderr)
        exit(1)
    }
    let title = String(localized: "Home scenes", bundle: bundle, locale: Locale(identifier: language))
    require(title == expected[language], "translation lookup failed for \(language)")
    let count = 5
    let plural = String(localized: "\(count) scenes", bundle: bundle, locale: Locale(identifier: language))
    require(plural == (language == "en" ? "5 scenes" : "5 сцен"), "plural lookup failed for \(language)")
    print("\(language): \(title) · \(plural)")
}
print("BUNDLE_CHECK_PASSED")
