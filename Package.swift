// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ClipboardHistoryApp",
    platforms: [
        .macOS(.v11)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ClipboardHistoryApp",
            dependencies: [],
            path: "Sources"
        )
    ]
)
