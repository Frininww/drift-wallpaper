// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Drift",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Drift", targets: ["Drift"])],
    targets: [
        .target(name: "DriftCore"),
        .executableTarget(name: "Drift", dependencies: ["DriftCore"], resources: [.copy("Resources/Aurora.mp4")]),
        .testTarget(name: "DriftCoreTests", dependencies: ["DriftCore"])
    ]
)
