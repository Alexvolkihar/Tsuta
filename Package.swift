// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tsuta",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tsuta", targets: ["Tsuta"])],
    targets: [
        .target(name: "TsutaCore"),
        .executableTarget(name: "Tsuta", dependencies: ["TsutaCore"]),
        // XCTest / swift-testing are not shipped with the Command Line Tools, so the checks
        // live in a plain executable: `swift run tsuta-selftest`.
        .executableTarget(name: "tsuta-selftest", dependencies: ["TsutaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
