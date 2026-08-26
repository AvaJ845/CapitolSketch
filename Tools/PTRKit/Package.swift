// swift-tools-version: 6.0
import PackageDescription

// Build-time tooling only. Everything that parses a filing lives in DisclosureKit, which
// is shared by this CLI, the app and the widget so that a filing read on device and the
// same filing read at build time cannot disagree.
//
// This package deliberately holds nothing platform-specific beyond "runs on a Mac": the
// Clerk serves its filing index as plain .txt at the same path as the ZIP, byte for byte,
// so there is no archive reader, no Process, and no macOS-only code path anywhere.
let package = Package(
    name: "PTRKit",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/DisclosureKit")
    ],
    targets: [
        .target(
            name: "PTRKit",
            dependencies: [.product(name: "DisclosureKit", package: "DisclosureKit")],
            path: "Sources/PTRKit"
        ),
        .executableTarget(
            name: "seedgen",
            dependencies: [
                "PTRKit",
                .product(name: "DisclosureKit", package: "DisclosureKit"),
            ],
            path: "Sources/seedgen"
        ),
    ]
)
