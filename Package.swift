// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DropCatCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DropCatCore", targets: ["DropCatCore"]),
    ],
    targets: [
        .target(name: "DropCatCore"),
        .testTarget(name: "DropCatCoreTests", dependencies: ["DropCatCore"]),
    ]
)
