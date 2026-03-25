// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dropbar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DropbarKit", path: "Sources/DropbarKit"),
        .executableTarget(name: "Dropbar", dependencies: ["DropbarKit"], path: "Sources/Dropbar"),
        .testTarget(name: "DropbarTests", dependencies: ["DropbarKit"], path: "Tests"),
    ]
)
