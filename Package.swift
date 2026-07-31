// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Darko",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Darko",
            path: "Sources/Darko",
            exclude: ["Info.plist"]
        )
    ]
)
