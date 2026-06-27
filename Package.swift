// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "coldfront",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "coldfront", targets: ["coldfront"]),
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
        .target(
            name: "FanControlCore"
        ),
        .target(
            name: "SMCControlTransport",
            dependencies: ["FanControlCore"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "coldfront",
            dependencies: ["FanProbeCore", "FanControlCore", "SMCControlTransport"]
        ),
        .executableTarget(
            name: "FanProbeCoreTestRunner",
            dependencies: ["FanProbeCore"],
            path: "Tests/FanProbeCoreTestRunner"
        ),
        .executableTarget(
            name: "FanControlCoreTestRunner",
            dependencies: ["FanControlCore", "SMCControlTransport"],
            path: "Tests/FanControlCoreTestRunner"
        )
    ]
)
