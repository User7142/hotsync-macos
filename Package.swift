// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HotSync",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // file checks and pilot-xfer transcript: no UI, unit-tested
        .target(
            name: "HotSyncCore",
            path: "Sources/HotSyncCore"
        ),
        .testTarget(
            name: "HotSyncCoreTests",
            dependencies: ["HotSyncCore"],
            path: "Tests/HotSyncCoreTests"
        ),
        .executableTarget(
            name: "HotSync",
            dependencies: ["HotSyncCore"],
            path: "Sources/HotSync",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreServices"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
