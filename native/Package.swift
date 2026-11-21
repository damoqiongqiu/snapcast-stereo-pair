// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacStereoPairNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StereoPairCore", targets: ["StereoPairCore"])
    ],
    targets: [
        .target(name: "StereoPairCore"),
        .testTarget(name: "StereoPairCoreTests", dependencies: ["StereoPairCore"])
    ]
)
