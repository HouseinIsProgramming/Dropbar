// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dropbar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Dropbar", path: "Sources")
    ]
)
