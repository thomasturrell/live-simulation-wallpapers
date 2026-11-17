// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CitySimulation",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "CityPreview", targets: ["CityPreview"])],
    targets: [
        .target(name: "CityEngine"),
        .target(name: "CityArt", dependencies: ["CityEngine"]),
        .executableTarget(name: "CityPreview", dependencies: ["CityArt", "CityEngine"]),
        .testTarget(name: "CityTests", dependencies: ["CityEngine", "CityArt"])
    ]
)
