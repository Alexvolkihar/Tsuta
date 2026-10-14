// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hanko",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HankoCore"),
        // XCTest / swift-testing are not shipped with the Command Line Tools, so the checks
        // live in a plain executable: `swift run hanko-selftest`.
        .executableTarget(name: "hanko-selftest", dependencies: ["HankoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
