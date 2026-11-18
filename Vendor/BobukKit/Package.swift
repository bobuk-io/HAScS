// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BobukKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BobukUI", targets: ["BobukUI"])],
    targets: [
        .target(name: "BobukUI", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "BobukUITests", dependencies: ["BobukUI"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "BobukUIGallery", dependencies: ["BobukUI"], path: "Examples/Gallery",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
