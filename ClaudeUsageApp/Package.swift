// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ClaudeUsageApp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "ClaudeUsageApp", targets: ["ClaudeUsageApp"]),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageApp",
            path: "Sources"
        ),
    ]
)
