// swift-tools-version: 6.0
@preconcurrency import PackageDescription

#if TUIST
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    baseSettings: .settings(
        configurations: [
            .debug(name: .debug),
            .release(name: .release),
        ]
    )
)
#endif

let package = Package(
    name: "LCdrData",
    dependencies: [
        .package(url: "https://github.com/danini-the-panini/kdl-swift", from: "2.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
    ]
)
