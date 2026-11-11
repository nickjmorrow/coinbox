// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "coinbox",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(name: "coinbox", dependencies: [
            .product(name: "CoinboxCore", package: "Core"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "coinboxTests", dependencies: ["coinbox", .product(name: "CoinboxCore", package: "Core")]),
    ]
)
