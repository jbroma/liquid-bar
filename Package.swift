// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "liquid-bar",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "liquid-bar", targets: ["LiquidBar"])],
    targets: [
        .target(name: "LiquidBarCore"),
        .executableTarget(
            name: "LiquidBar",
            dependencies: ["LiquidBarCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "LiquidBarCoreTests", dependencies: ["LiquidBarCore"]),
    ]
)
