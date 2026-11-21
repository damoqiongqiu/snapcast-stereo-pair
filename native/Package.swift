// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStereoPairNative",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StereoPairCore", targets: ["StereoPairCore"]),
        .executable(name: "StereoPairAgent", targets: ["StereoPairAgent"]),
        .executable(name: "mac-stereo-pairctl", targets: ["mac-stereo-pairctl"]),
        .executable(name: "MacStereoPair", targets: ["MacStereoPair"])
    ],
    targets: [
        .target(name: "StereoPairMetricsBridge"),
        .target(name: "StereoPairCore", dependencies: ["StereoPairMetricsBridge"]),
        .executableTarget(name: "StereoPairAgent", dependencies: ["StereoPairCore"]),
        .executableTarget(name: "mac-stereo-pairctl", dependencies: ["StereoPairCore"]),
        .executableTarget(
            name: "MacStereoPair",
            dependencies: ["StereoPairCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "StereoPairCoreTests", dependencies: ["StereoPairCore"])
    ]
)
