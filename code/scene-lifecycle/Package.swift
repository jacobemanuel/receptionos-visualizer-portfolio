// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SceneLifecycle",
    platforms: [.macOS(.v13), .iOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "SceneLifecycle", targets: ["SceneLifecycle"]),
    ],
    targets: [
        .target(name: "SceneLifecycle"),
        .testTarget(name: "SceneLifecycleTests", dependencies: ["SceneLifecycle"]),
    ]
)
