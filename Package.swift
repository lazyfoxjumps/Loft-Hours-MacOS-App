// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoftHours",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "LoftHours",
            path: "Sources/LoftHours"
        )
    ]
)
