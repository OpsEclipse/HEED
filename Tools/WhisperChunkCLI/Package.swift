// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhisperChunkCLI",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "WhisperChunkCLI", targets: ["WhisperChunkCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", revision: "deb1cb6a27256c7b01f5d3d2e7dc1dcc330b5d01"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperChunkCLI",
            dependencies: [
                .product(name: "SwiftWhisper", package: "SwiftWhisper"),
            ]
        ),
    ]
)
