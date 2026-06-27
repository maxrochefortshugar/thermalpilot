// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mlx-chill",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mlx-chill", targets: ["mlx-chill"]),
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
            name: "mlx-chill",
            dependencies: ["FanProbeCore"]
        ),
        .executableTarget(
            name: "FanProbeCoreTestRunner",
            dependencies: ["FanProbeCore"],
            path: "Tests/FanProbeCoreTestRunner"
        )
    ]
)
