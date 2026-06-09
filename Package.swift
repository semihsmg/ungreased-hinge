// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ungreased-hinge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "UngreasedHinge",
            resources: [.copy("Resources/creak.wav")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
