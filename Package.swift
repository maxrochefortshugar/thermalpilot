// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "thermalpilot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "thermalpilot", targets: ["thermalpilot"]),
        .library(name: "FanProbeCore", targets: ["FanProbeCore"])
    ],
    targets: [
        .target(
            name: "CSMC",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit")
            ]
        ),
        .target(
            name: "FanProbeCore",
            dependencies: ["CSMC"]
        ),
        .executableTarget(
            name: "thermalpilot",
            dependencies: ["FanProbeCore"]
        ),
        .executableTarget(
            name: "FanProbeCoreTestRunner",
            dependencies: ["FanProbeCore"],
            path: "Tests/FanProbeCoreTestRunner"
        )
    ]
)
