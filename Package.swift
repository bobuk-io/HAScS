// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HAScS",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HAScSCore", targets: ["HAScSCore"]),
        .executable(name: "HAScS", targets: ["HAScS"]),
    ],
    dependencies: [.package(path: "Vendor/BobukKit")],
    targets: [
        .target(name: "HAScSCore", dependencies: [
            .product(name: "BobukCore", package: "BobukKit"),
            .product(name: "BobukSystem", package: "BobukKit"),
        ],
                resources: [.process("Resources")]),
        .executableTarget(name: "HAScS", dependencies: [
            "HAScSCore",
            .product(name: "BobukCore", package: "BobukKit"),
            .product(name: "BobukSystem", package: "BobukKit"),
            .product(name: "BobukUI", package: "BobukKit"),
        ]),
        .testTarget(name: "HAScSCoreTests", dependencies: ["HAScSCore"]),
        .testTarget(name: "HAScSAppTests", dependencies: [
            "HAScS", "HAScSCore",
            .product(name: "BobukCore", package: "BobukKit"),
            .product(name: "BobukUI", package: "BobukKit"),
        ]),
    ]
)
