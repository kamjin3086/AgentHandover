// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenMimicApp",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "OpenMimicApp",
            path: "Sources/OpenMimicApp",
            exclude: ["Info.plist"]
        ),
    ]
)
