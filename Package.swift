// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "liquid-bar",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "liquid-bar", targets: ["LiquidBar"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "LiquidBarCore"),
        .executableTarget(
            name: "LiquidBar",
            dependencies: ["LiquidBarCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // `make app` puts Sparkle.framework in the bundle's Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "LiquidBarCoreTests", dependencies: ["LiquidBarCore"]),
    ]
)
