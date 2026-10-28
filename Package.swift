// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Blip", path: "Sources/Blip"),
    ]
)
