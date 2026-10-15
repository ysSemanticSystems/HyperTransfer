// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HyperTransfer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HyperTransfer", targets: ["HyperTransfer"])
    ],
    targets: [
        .target(name: "HyperTransferCore"),
        .executableTarget(
            name: "HyperTransfer",
            dependencies: ["HyperTransferCore"]
        ),
        .executableTarget(
            name: "HyperTransferChecks",
            dependencies: ["HyperTransferCore"],
            path: "Tests/HyperTransferCoreTests",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
