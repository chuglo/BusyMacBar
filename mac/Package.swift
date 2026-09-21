// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BusyMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BusyMac", path: "Sources/BusyMac")
    ]
)
