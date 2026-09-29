// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HotSync",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "HotSync",
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
