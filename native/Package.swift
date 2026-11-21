// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStereoPairNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StereoPairCore", targets: ["StereoPairCore"]),
        .executable(name: "StereoPairAgent", targets: ["StereoPairAgent"]),
        .executable(name: "mac-stereo-pairctl", targets: ["mac-stereo-pairctl"])
    ],
    targets: [
        .target(name: "StereoPairMetricsBridge"),
        .target(name: "StereoPairCore", dependencies: ["StereoPairMetricsBridge"]),
        .executableTarget(name: "StereoPairAgent", dependencies: ["StereoPairCore"]),
        .executableTarget(name: "mac-stereo-pairctl", dependencies: ["StereoPairCore"]),
        .testTarget(name: "StereoPairCoreTests", dependencies: ["StereoPairCore"])
    ]
)
