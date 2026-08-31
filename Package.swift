// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Unico",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "Unico", targets: ["UnicoApp"])],
    targets: [
        .target(name: "UnicoCore"),
        .executableTarget(name: "UnicoApp", dependencies: ["UnicoCore"]),
        .testTarget(name: "UnicoCoreTests", dependencies: ["UnicoCore", "UnicoApp"])
    ],
    swiftLanguageModes: [.v5]
)
