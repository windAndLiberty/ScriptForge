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
    targets: [
        .executableTarget(
            name: "ScriptForgeMac",
            path: "Sources/ScriptForgeMac"
        )
    ]
)
