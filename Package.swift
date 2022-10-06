// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Theo",
    platforms: [
        .macOS(.v12),
        .iOS(.v13),
        .tvOS(.v12)
    ],
    products: [
        .library(name: "Theo", targets: ["Theo"])
    ],
    dependencies: [
      .package(url: "https://github.com/bynelus/Bolt-swift.git", branch: "dev/5.2.1")
    ],
    targets: [
        .target(
            name: "Theo",
            dependencies: [
              .product(name: "Bolt", package: "Bolt-swift"),
            ]),
        .testTarget(
            name: "TheoTests",
            dependencies: ["Theo"])
    ]
)
