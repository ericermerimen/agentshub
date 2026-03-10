// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentPing",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentPingApp", targets: ["AgentPing"]),
        .executable(name: "agentping", targets: ["AgentPingCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", "1.3.0"..<"1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentPing",
            dependencies: ["AgentPingCore"],
            path: "Sources/AgentPing",
            exclude: ["Info.plist", "Assets"]
        ),
        .executableTarget(
            name: "AgentPingCLI",
            dependencies: [
                "AgentPingCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AgentPingCLI"
        ),
        .target(
            name: "AgentPingCore",
            path: "Sources/AgentPingCore"
        ),
        .testTarget(
            name: "AgentPingCoreTests",
            dependencies: ["AgentPingCore"],
            path: "Tests/AgentPingCoreTests"
        ),
    ]
)
