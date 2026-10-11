// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NucLED",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NucLED", targets: ["NucLED"])],
    targets: [
        .executableTarget(
            name: "NucLED",
            path: "Sources/NucLED",
            resources: [.copy("Resources")]
        )
    ]
)
