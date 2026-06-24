// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "M4FanControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "M4FanCore", targets: ["M4FanCore"]),
        .executable(name: "m4fan", targets: ["M4FanCLI"]),
        .executable(name: "M4FanControl", targets: ["M4FanControlApp"]),
        .executable(name: "M4FanHelper", targets: ["M4FanHelper"])
    ],
    targets: [
        .target(
            name: "M4FanCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "M4FanCLI",
            dependencies: ["M4FanCore"]
        ),
        .executableTarget(
            name: "M4FanControlApp",
            dependencies: ["M4FanCore"]
        ),
        .executableTarget(
            name: "M4FanHelper",
            dependencies: ["M4FanCore"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "M4FanCoreTests",
            dependencies: ["M4FanCore"]
        )
    ]
)
