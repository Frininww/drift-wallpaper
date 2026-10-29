// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Drift",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Drift", targets: ["Drift"])],
    targets: [
        .target(name: "DriftCore"),
        .executableTarget(name: "Drift", dependencies: ["DriftCore"], resources: [
            .copy("Resources/Aurora.mp4"), .copy("Resources/Aurora4K.mp4"),
            .process("Resources/en.lproj"), .process("Resources/ru.lproj")
        ]),
        .testTarget(name: "DriftCoreTests", dependencies: ["DriftCore"]),
        .testTarget(name: "DriftMediaTests", dependencies: ["Drift", "DriftCore"])
    ]
)
