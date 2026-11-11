// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoinboxCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "CoinboxCore", targets: ["CoinboxCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")],
    targets: [
        .target(name: "CoinboxCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "CoinboxCoreTests", dependencies: ["CoinboxCore", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
