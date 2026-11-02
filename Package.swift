// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyZmanMac",
    defaultLocalization: "he",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Elyahu41/KosherSwift.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MyZmanMac",
            dependencies: ["KosherSwift"],
            path: "Sources/MyZmanMac"
        ),
        // WidgetKit extension; its model files are symlinks into Sources/MyZmanMac.
        .executableTarget(
            name: "MyZmanWidget",
            dependencies: ["KosherSwift"],
            path: "Sources/MyZmanWidget"
        ),
    ]
)
