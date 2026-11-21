// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GameOfLife",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WallpaperPalette", targets: ["WallpaperPalette"]),
        .executable(name: "GameOfLife", targets: ["LifeApp"]),
        .library(name: "LifeSaver", type: .dynamic, targets: ["LifeSaver"])
    ],
    targets: [
        .target(name: "LifeEngine"),
        .target(name: "WallpaperPalette"),
        .target(name: "LifeArt", dependencies: ["LifeEngine", "WallpaperPalette"]),
        .executableTarget(name: "LifeApp", dependencies: ["LifeArt"]),
        .target(name: "LifeSaver", dependencies: ["LifeArt"]),
        .testTarget(name: "LifeTests", dependencies: ["LifeEngine", "LifeArt", "LifeSaver"])
    ]
)
