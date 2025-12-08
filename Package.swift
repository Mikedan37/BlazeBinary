// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
    targets: [
        .target(
            name: "BlazeBinary"
        ),
        .testTarget(
            name: "BlazeBinaryTests",
            dependencies: ["BlazeBinary"]
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
