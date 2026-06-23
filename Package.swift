// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "AgentBar", targets: ["AgentBar"]),
    ],
    targets: [
        .executableTarget(
            name: "AgentBar",
            path: "Sources/AgentBar"
        ),
    ]
)
