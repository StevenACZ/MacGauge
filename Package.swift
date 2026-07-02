// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacFan",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacFanCore", targets: ["MacFanCore"]),
        .executable(name: "macfan", targets: ["MacFanCLI"]),
        // Named MacFanApp because a "MacFan" product would collide with the
        // "macfan" CLI binary on case-insensitive filesystems.
        .executable(name: "MacFanApp", targets: ["MacFanApp"]),
        .executable(name: "MacFanHelper", targets: ["MacFanHelper"]),
    ],
    targets: [
        .target(
            name: "MacFanCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "MacFanCLI",
            dependencies: ["MacFanCore"]
        ),
        .executableTarget(
            name: "MacFanApp",
            dependencies: ["MacFanCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MacFanHelper",
            dependencies: ["MacFanCore"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .unsafeFlags(
                    [
                        "-Xlinker", "-sectcreate",
                        "-Xlinker", "__TEXT",
                        "-Xlinker", "__info_plist",
                        "-Xlinker", "Resources/MacFanHelperInfo.plist",
                    ], .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "MacFanCoreTests",
            dependencies: ["MacFanCore"]
        ),
    ]
)
