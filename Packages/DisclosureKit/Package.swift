// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisclosureKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "DisclosureKit", targets: ["DisclosureKit"])
    ],
    targets: [
        .target(name: "DisclosureKit"),
        .testTarget(
            name: "DisclosureKitTests",
            dependencies: ["DisclosureKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
