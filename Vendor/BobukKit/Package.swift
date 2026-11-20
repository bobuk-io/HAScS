// swift-tools-version: 6.2
import PackageDescription

// Every module uses Swift 5 language mode, like the apps that vendor this package.
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "BobukKit",
    platforms: [.macOS(.v14)],
    products: [
        // Foundation only: safe for command-line companions and *Core targets without AppKit.
        .library(name: "BobukCore", targets: ["BobukCore"]),
        // AppKit, Carbon, Security and ServiceManagement services.
        .library(name: "BobukSystem", targets: ["BobukSystem"]),
        // Window shells, panels, strips, glyphs, palettes and picker components.
        .library(name: "BobukUI", targets: ["BobukUI"]),
        // Homebrew updates and the Sparkle seam. Sparkle itself stays in the app's Package.swift.
        .library(name: "BobukUpdates", targets: ["BobukUpdates"]),
        // Test-only helpers: temporary folders, fake executables and app bundles, isolated defaults.
        .library(name: "BobukTestSupport", targets: ["BobukTestSupport"]),
    ],
    targets: [
        .target(name: "BobukCore", swiftSettings: v5),
        .target(name: "BobukSystem", dependencies: ["BobukCore"], swiftSettings: v5),
        .target(name: "BobukUI", dependencies: ["BobukCore", "BobukSystem"], swiftSettings: v5),
        .target(name: "BobukUpdates", dependencies: ["BobukCore", "BobukSystem", "BobukUI"], swiftSettings: v5),
        .target(name: "BobukTestSupport", dependencies: ["BobukCore"], swiftSettings: v5),
        .testTarget(name: "BobukCoreTests", dependencies: ["BobukCore", "BobukTestSupport"], swiftSettings: v5),
        .testTarget(name: "BobukSystemTests", dependencies: ["BobukSystem", "BobukTestSupport"], swiftSettings: v5),
        .testTarget(name: "BobukUITests", dependencies: ["BobukUI", "BobukTestSupport"], swiftSettings: v5),
        .testTarget(name: "BobukUpdatesTests", dependencies: ["BobukUpdates", "BobukTestSupport"], swiftSettings: v5),
        .executableTarget(name: "BobukUIGallery", dependencies: ["BobukUI", "BobukUpdates"], path: "Examples/Gallery",
                          swiftSettings: v5),
    ]
)
