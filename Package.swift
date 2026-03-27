// swift-tools-version: 5.9
// FlinkuSDK 0.3.0
import PackageDescription

let package = Package(
    name: "FlinkuSDK",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "FlinkuSDK",
            targets: ["FlinkuSDK"]
        ),
    ],
    targets: [
        .target(
            name: "FlinkuSDK",
            dependencies: []
        ),
        .testTarget(
            name: "FlinkuSDKTests",
            dependencies: ["FlinkuSDK"]
        ),
    ]
)
