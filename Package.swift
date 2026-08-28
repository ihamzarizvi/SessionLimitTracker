// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionLimitTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SessionLimitTracker", targets: ["SessionLimitTracker"])
    ],
    targets: [
        .executableTarget(
            name: "SessionLimitTracker",
            path: "Sources/SessionLimitTracker"
        ),
        .testTarget(
            name: "SessionLimitTrackerTests",
            dependencies: ["SessionLimitTracker"],
            path: "Tests/SessionLimitTrackerTests"
        )
    ]
)
