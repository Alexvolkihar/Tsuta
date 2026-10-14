// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hanko",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HankoCore"),
    ],
    swiftLanguageModes: [.v5]
)
