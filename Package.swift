// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HyperTransfer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyperTransfer", targets: ["HyperTransfer"])
    ],
    targets: [
        .target(
            name: "HyperTransferVerbs",
            path: "Sources/HyperTransferVerbs",
            publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("rdma")]
        ),
        .target(
            name: "HyperTransferCore",
            dependencies: ["HyperTransferVerbs"]
        ),
        .executableTarget(
            name: "HyperTransfer",
            dependencies: ["HyperTransferCore"]
        ),
        .executableTarget(
            name: "HyperTransferJoin",
            dependencies: ["HyperTransferVerbs"]
        ),
        .executableTarget(
            name: "HyperTransferChecks",
            dependencies: ["HyperTransferCore"],
            path: "Tests/HyperTransferCoreTests",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
