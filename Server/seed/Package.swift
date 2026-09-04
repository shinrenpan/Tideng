// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimingSeed",
    platforms: [.macOS(.v14)],
    dependencies: [
        // FHIR 命名空間與 LOINC 常數——與 app 共用同一份定義，不另外抄一遍字串
        .package(path: "../../App/Packages/FHIRCore"),
        // TW Core 的身分證字號、profile 宣告與 SHALL 欄位檢查
        .package(url: "https://github.com/shinrenpan/TWCoreFHIRModels.git", exact: "1.0.0"),
        .package(url: "https://github.com/apple/FHIRModels.git", exact: "0.9.3")
    ],
    targets: [
        .executableTarget(
            name: "SimingSeed",
            dependencies: [
                "FHIRCore",
                .product(name: "ModelsR4", package: "FHIRModels"),
                .product(name: "TWCoreFHIRModels", package: "TWCoreFHIRModels")
            ]
        )
    ]
)
