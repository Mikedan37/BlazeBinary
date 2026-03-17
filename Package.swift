// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Compatible with Swift 5.9+ and Swift 6.x

import PackageDescription

let package = Package(
    name: "BlazeBinary",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "BlazeBinary",
            targets: ["BlazeBinary"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "BlazeBinary",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "BlazeBinaryTests",
            dependencies: [
                "BlazeBinary",
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "BlazeBinaryBenchmarks",
            dependencies: ["BlazeBinary"]
        ),
        .testTarget(
            name: "BlazeBinaryFuzzTests",
            dependencies: ["BlazeBinary"]
        ),
    ]
)
