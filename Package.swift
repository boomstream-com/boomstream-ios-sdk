// swift-tools-version: 6.0
import PackageDescription

// Zero third-party dependencies — намеренно (docs/SDK_ARCHITECTURE.md §3).
// Добавление dependency требует board-решения; CI zero-deps-gate падает на `.package(`.
let package = Package(
    name: "BoomstreamSDK",
    platforms: [
        .iOS(.v15),
        // macOS min нужен только для host-сборки и `swift test` (типы кроссплатформенные);
        // продуктовая платформа SDK — iOS.
        .macOS(.v12),
    ],
    products: [
        .library(name: "BoomstreamAPI", targets: ["BoomstreamAPI"]),
        .library(name: "BoomstreamPlayer", targets: ["BoomstreamPlayer"]),
        .library(name: "BoomstreamOffline", targets: ["BoomstreamOffline"]),
    ],
    targets: [
        .target(name: "BoomstreamAPI"),
        .target(name: "BoomstreamPlayer", dependencies: ["BoomstreamAPI"]),
        .target(name: "BoomstreamOffline", dependencies: ["BoomstreamAPI"]),
        .testTarget(name: "BoomstreamAPITests", dependencies: ["BoomstreamAPI"]),
        .testTarget(name: "BoomstreamPlayerTests", dependencies: ["BoomstreamPlayer"]),
        .testTarget(name: "BoomstreamOfflineTests", dependencies: ["BoomstreamOffline"]),
    ]
)
