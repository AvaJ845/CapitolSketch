// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisclosureKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "DisclosureKit", targets: ["DisclosureKit"])
    ],
    targets: [
        .target(
            name: "DisclosureKit",
            swiftSettings: [
                // The Senate eFD portal scraper (SenateFilingIndex / SenateFetcher /
                // SenatePTRParser) is `#if SEEDGEN`-gated so it never enters the iOS app
                // or widget binary. It is still needed by the build-time `seedgen` CLI
                // and by the Senate tests, both of which build this library for macOS —
                // so the define is on for macOS builds only. Xcode builds this package
                // for iOS when compiling the app, where the condition is false and the
                // Senate code is excluded.
                .define("SEEDGEN", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "DisclosureKitTests",
            dependencies: ["DisclosureKit"],
            resources: [.copy("Fixtures")],
            // Keeps SenateParserTests / SenateLiveTests and the senate/ fixtures
            // compiling under `swift test`.
            swiftSettings: [.define("SEEDGEN")]
        ),
    ]
)
