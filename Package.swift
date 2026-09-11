// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MatterMemory",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MatterMemory",
            path: "Sources/MatterMemory",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
