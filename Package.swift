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
            path: "Sources/MyZmanWidget",
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            // Like Xcode's widget targets: start in NSExtensionMain, which connects the process to the
            // extension system (a plain main() runs but is never registered, so the widget never shows).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])]
        ),
    ]
)
