// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macos-defaults",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(name: "MacosDefaultsCore"),
        .executableTarget(
            name: "macos-defaults",
            dependencies: [
                "MacosDefaultsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "MacosDefaultsCoreTests",
            dependencies: ["MacosDefaultsCore"]
        ),
    ]
)
