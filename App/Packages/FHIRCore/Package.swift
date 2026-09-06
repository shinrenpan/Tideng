// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FHIRCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FHIRCore", targets: ["FHIRCore"])
    ],
    dependencies: [
        // 與 Siming 鎖同一版本。兩邊的 wire format 必須一致，升版時要一起動。
        .package(url: "https://github.com/apple/FHIRModels.git", exact: "0.9.3")
    ],
    targets: [
        .target(
            name: "FHIRCore",
            dependencies: [.product(name: "ModelsR4", package: "FHIRModels")]
        ),
        .testTarget(name: "FHIRCoreTests", dependencies: ["FHIRCore"])
    ]
)
