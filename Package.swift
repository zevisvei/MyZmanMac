// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyZmanMac",
    defaultLocalization: "he",
    platforms: [.macOS(.v14)],
    dependencies: [
        // KosherSwift 2.0.0 with crash fixes; see Vendor/KosherSwift/PATCHES.md.
        .package(path: "Vendor/KosherSwift"),
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
