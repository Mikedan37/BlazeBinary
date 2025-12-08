// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "blaze",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "blaze",
            dependencies: [
                .product(name: "BlazeBinary", package: "BlazeBinary")
            ]
        )
    ]
)

