// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartAuth",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SmartAuth", targets: ["SmartAuth"])
    ],
    dependencies: [
        // 依賴方向刻意是 SmartAuth → FHIRClient：SmartAuth 實作 FHIRClient 定義的
        // TokenProviding，FHIRClient 對 SMART 流程一無所知，可以完全脫離 auth 測試。
        .package(path: "../FHIRClient")
    ],
    targets: [
        .target(name: "SmartAuth", dependencies: ["FHIRClient"]),
        .testTarget(name: "SmartAuthTests", dependencies: ["SmartAuth"])
    ]
)
