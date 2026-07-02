// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacFan",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacFanCore", targets: ["MacFanCore"]),
        .executable(name: "macfan", targets: ["MacFanCLI"]),
        .executable(name: "MacFan", targets: ["MacFanApp"]),
        .executable(name: "MacFanHelper", targets: ["MacFanHelper"])
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
            dependencies: ["MacFanCore"]
        ),
        .executableTarget(
            name: "MacFanHelper",
            dependencies: ["MacFanCore"],
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/MacFanHelperInfo.plist"
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "MacFanCoreTests",
            dependencies: ["MacFanCore"]
        )
    ]
)
