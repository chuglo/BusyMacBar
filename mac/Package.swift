// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BusyMacBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BusyMacBar", path: "Sources/BusyMacBar")
    ]
)
