// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CosimmetryLife",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CosimmetryLife", targets: ["LifeApp"]),
        .library(name: "LifeSaver", type: .dynamic, targets: ["LifeSaver"])
    ],
    targets: [
        .target(name: "LifeEngine"),
        .target(name: "LifeArt", dependencies: ["LifeEngine"]),
        .executableTarget(name: "LifeApp", dependencies: ["LifeArt"]),
        .target(name: "LifeSaver", dependencies: ["LifeArt"]),
        .testTarget(name: "LifeTests", dependencies: ["LifeEngine", "LifeArt", "LifeSaver"])
    ]
)
