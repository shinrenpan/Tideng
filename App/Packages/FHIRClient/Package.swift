// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FHIRClient",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FHIRClient", targets: ["FHIRClient"])
    ],
    dependencies: [
        .package(path: "../FHIRCore"),
        .package(url: "https://github.com/apple/FHIRModels.git", exact: "0.9.3")
    ],
    targets: [
        .target(
            name: "FHIRClient",
            dependencies: ["FHIRCore", .product(name: "ModelsR4", package: "FHIRModels")]
        ),
        .testTarget(name: "FHIRClientTests", dependencies: ["FHIRClient", "FHIRCore"])
    ]
)
