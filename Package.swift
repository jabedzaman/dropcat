// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SSHDropCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SSHDropCore", targets: ["SSHDropCore"]),
    ],
    targets: [
        .target(name: "SSHDropCore"),
        .testTarget(name: "SSHDropCoreTests", dependencies: ["SSHDropCore"]),
    ]
)
