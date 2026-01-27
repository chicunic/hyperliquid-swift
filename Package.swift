// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hyperliquid-swift",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "HyperliquidSwift", targets: ["HyperliquidSwift"])
    ],
    dependencies: [
        // secp256k1 - Elliptic curve cryptography for signing
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.21.0"),
        // CryptoSwift - Keccak256 hashing
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.9.0"),
        // BigInt - Arbitrary precision integers for MessagePack
        .package(url: "https://github.com/attaswift/BigInt", from: "5.7.0"),
        // OrderedDictionary for consistent msgpack serialization order
        .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
        // OHHTTPStubs for VCR-style HTTP mocking in tests
        .package(url: "https://github.com/AliSoftware/OHHTTPStubs", from: "9.1.0"),
    ],
    targets: [
        .target(
            name: "HyperliquidSwift",
            dependencies: [
                .product(name: "P256K", package: "secp256k1.swift"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ]
        ),
        .testTarget(
            name: "HyperliquidSwiftTests",
            dependencies: [
                "HyperliquidSwift",
                .product(name: "OHHTTPStubsSwift", package: "OHHTTPStubs"),
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
