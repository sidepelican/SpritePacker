// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SpritePacker",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", .upToNextMinor(from: "0.5.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "SpritePacker",
            dependencies: [
                "CZlib",
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .systemLibrary(
            name: "CZlib"
        ),
        .testTarget(
            name: "SpritePackerTests",
            dependencies: ["SpritePacker", "CZlib"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
