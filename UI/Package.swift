// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoinboxUI",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "CoinboxUI", targets: ["CoinboxUI"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "CoinboxUI", dependencies: [.product(name: "CoinboxCore", package: "Core")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CoinboxUITests", dependencies: ["CoinboxUI", .product(name: "CoinboxCore", package: "Core")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
