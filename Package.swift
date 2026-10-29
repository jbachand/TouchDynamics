// swift-tools-version: 5.9
import PackageDescription

let strictConcurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "TouchDynamics",
    platforms: [
        .iOS(.v16),
        // macOS is listed only so the platform-neutral core (engine, physics,
        // configuration) builds and tests with `swift build` on a Mac host.
        // UIKit, SwiftUI, Core Animation and Metal integrations are iOS-only.
        .macOS(.v13),
    ],
    products: [
        .library(name: "TouchDynamics", targets: ["TouchDynamics"]),
    ],
    targets: [
        .target(
            name: "TouchDynamics",
            path: "Sources/TouchDynamics",
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "TouchDynamicsTests",
            dependencies: ["TouchDynamics"],
            path: "Tests/TouchDynamicsTests",
            swiftSettings: strictConcurrency
        ),
    ]
)
