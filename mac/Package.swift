// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirVibes",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AirVibes", path: "Sources/AirVibes")
    ]
)
