// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ScriptForgeMac",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScriptForgeMac", targets: ["ScriptForgeMac"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/weichsel/ZIPFoundation.git",
            exact: "0.9.20"
        ),
    ],
    targets: [
        .executableTarget(
            name: "ScriptForgeMac",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/ScriptForgeMac",
            resources: [
                .copy("Resources/ScriptForgeAura.png"),
            ]
        ),
        .testTarget(
            name: "ScriptForgeMacTests",
            dependencies: [
                "ScriptForgeMac",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Tests/ScriptForgeMacTests"
        ),
    ]
)
