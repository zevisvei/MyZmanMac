// swift-tools-version: 5.9
// KosherSwift 2.0.0 (https://github.com/Elyahu41/KosherSwift, revision e97a6f38), vendored with the fixes in PATCHES.md.
import PackageDescription

let package = Package(
    name: "KosherSwift",
    // Same floor as the app, so nothing links the old Swift back-deployment libraries.
    platforms: [.macOS(.v14)],
    products: [.library(name: "KosherSwift", targets: ["KosherSwift"])],
    targets: [.target(name: "KosherSwift")]
)
