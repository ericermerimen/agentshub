// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentsHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentsHub", targets: ["AgentsHub"]),
        .executable(name: "agentshub", targets: ["AgentsHubCLI"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AgentsHub",
            dependencies: ["AgentsHubCore"],
            path: "Sources/AgentsHub"
        ),
        .executableTarget(
            name: "AgentsHubCLI",
            dependencies: ["AgentsHubCore"],
            path: "Sources/AgentsHubCLI"
        ),
        .target(
            name: "AgentsHubCore",
            path: "Sources/AgentsHubCore"
        ),
        .testTarget(
            name: "AgentsHubCoreTests",
            dependencies: ["AgentsHubCore"],
            path: "Tests/AgentsHubCoreTests"
        ),
    ]
)
