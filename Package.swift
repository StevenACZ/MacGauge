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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
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
            dependencies: [
                "MacFanCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                // Sparkle.framework is staged into Contents/Frameworks by
                // scripts/build_and_run.sh; the bundle binary resolves it here.
                .unsafeFlags(
                    [
                        "-Xlinker", "-rpath",
                        "-Xlinker", "@executable_path/../Frameworks",
                    ], .when(platforms: [.macOS]))
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
        .testTarget(
            name: "MacFanAppTests",
            dependencies: ["MacFanApp"]
        ),
    ]
)
