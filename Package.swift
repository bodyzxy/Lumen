// swift-tools-version:5.9
// Lumen —— 轻量的 Mac 调色软件 / A lightweight photo color-grading app for Mac
// 只依赖系统自带框架（SwiftUI / Core Image / Metal），打包后只有几 MB。

import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Lumen",
            path: "Sources/Lumen",
            resources: [
                .copy("Resources/AppIcon.png")
            ]
        ),
        .executableTarget(
            name: "LumenMCP",
            path: "Sources/LumenMCP"
        )
    ]
)
