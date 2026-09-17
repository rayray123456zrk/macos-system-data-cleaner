// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSpaceGuard",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacSpaceGuardCore", targets: ["MacSpaceGuardCore"]),
        .executable(name: "macspaceguard-helper", targets: ["MacSpaceGuardHelper"])
    ],
    targets: [
        .target(name: "MacSpaceGuardCore"),
        .executableTarget(
            name: "MacSpaceGuardHelper",
            dependencies: ["MacSpaceGuardCore"]
        ),
        .testTarget(
            name: "MacSpaceGuardCoreTests",
            dependencies: ["MacSpaceGuardCore"]
        )
    ]
)
