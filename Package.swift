// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Figurehead",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Figurehead",
            path: "Sources/Figurehead"
        ),
    ]
)
