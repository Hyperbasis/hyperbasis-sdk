// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Hyperbasis",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Hyperbasis",
            targets: ["Hyperbasis"]
        ),
    ],
    targets: [
        .target(
            name: "Hyperbasis",
            path: "Sources/Hyperbasis"
        ),
        .testTarget(
            name: "HyperbasisTests",
            dependencies: ["Hyperbasis"],
            path: "Tests/HyperbasisTests"
        ),
    ]
)
