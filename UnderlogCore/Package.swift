// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnderlogCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(name: "UnderlogCore", targets: ["UnderlogCore"]),
    ],
    targets: [
        .target(name: "UnderlogCore"),
        .testTarget(name: "UnderlogCoreTests", dependencies: ["UnderlogCore"]),
    ]
)
