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
    targets: [
        .target(name: "HAScSCore", resources: [.process("Resources")]),
        .executableTarget(name: "HAScS", dependencies: ["HAScSCore"]),
        .testTarget(name: "HAScSCoreTests", dependencies: ["HAScSCore"]),
        .testTarget(name: "HAScSAppTests", dependencies: ["HAScS", "HAScSCore"]),
    ]
)
