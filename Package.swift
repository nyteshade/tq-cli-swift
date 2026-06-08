// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "tq",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/toon-format/toon-swift.git", from: "0.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "tq",
            dependencies: [
                .product(name: "ToonFormat", package: "toon-swift"),
            ]
        ),
    ]
)
