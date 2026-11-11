// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DockMorph",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DockMorph", path: "Sources/DockMorph")
    ]
)
