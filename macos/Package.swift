// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MSIMonitorControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "MSIControl",
            targets: ["MSIControl"]
        ),
        .executable(
            name: "MSIControlApp",
            targets: ["MSIControlApp"]
        ),
    ],
    targets: [
        .target(
            name: "MSIControl",
            path: "Sources/MSIControl"
        ),
        .executableTarget(
            name: "MSIControlApp",
            dependencies: ["MSIControl"],
            path: "Sources/MSIControlApp",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "MSIControlTests",
            dependencies: ["MSIControl"],
            path: "Tests/MSIControlTests"
        ),
    ]
)
