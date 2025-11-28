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
    dependencies: [
        // Supabase Swift SDK for cloud storage
        // Note: Cloud store has placeholder URLSession implementation
        // Replace with Supabase SDK calls when ready for production
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Hyperbasis",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/Hyperbasis"
        ),
        .testTarget(
            name: "HyperbasisTests",
            dependencies: ["Hyperbasis"],
            path: "Tests/HyperbasisTests"
        ),
    ]
)
