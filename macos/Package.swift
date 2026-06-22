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
            resources: [
                // Menu-bar template icon (monochrome, transparent). Loaded at
                // runtime via Bundle.module and marked isTemplate so macOS tints it.
                .copy("Resources/menubar-icon.pdf"),
            ],
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
