// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexAgentBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CodexAgentBar", targets: ["CodexAgentBar"]),
    ],
    targets: [
        .executableTarget(
            name: "CodexAgentBar",
            path: "Sources/CodexAgentBar"
        ),
    ]
)
