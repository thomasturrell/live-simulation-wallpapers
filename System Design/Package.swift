// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SystemDesign",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "DesignPreview", targets: ["DesignPreview"])],
    dependencies: [.package(name: "GameOfLife", path: "../Game of Life")],
    targets: [
        .target(name: "DesignEngine", resources: [.process("Catalogue")]),
        .target(name: "DesignArt", dependencies: [
            "DesignEngine", .product(name: "WallpaperPalette", package: "GameOfLife")
        ]),
        .executableTarget(name: "DesignPreview", dependencies: [
            "DesignArt", "DesignEngine", .product(name: "WallpaperPalette", package: "GameOfLife")
        ]),
        .testTarget(name: "DesignTests", dependencies: ["DesignArt", "DesignEngine"])
    ]
)
