import Foundation
import FHIRCore

/// 一次 FHIR search 查詢。
///
/// 刻意不做成泛用的 query DSL——MVP 只需要少數幾條固定查詢，把它們列成具名的 factory，
/// 等於把「這個 app 對 server 的要求」寫成一份可讀的清單，也方便對照 server 端的相容性。
public struct FHIRSearch: Sendable, Equatable {

    public struct Item: Sendable, Equatable {
        public let name: String
        public let value: String

        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public let resourceType: String
    public let parameters: [Item]

    public init(resourceType: String, parameters: [Item]) {
        self.resourceType = resourceType
        self.parameters = parameters
    }
}

// MARK: - MVP 需要的查詢

public extension FHIRSearch {

    /// 病人清單。
    static func patients(count: Int = 50) -> FHIRSearch {
        FHIRSearch(
            resourceType: "Patient",
            parameters: [
                .init("_count", String(count)),
                .init("_sort", "family")
            ]
        )
    }

    /// 進行中的就診。
    ///
    /// 診所是門診、醫院是住院，資料來源同樣是 Encounter——差別只在畫面怎麼分組，
    /// 所以查詢這一層不區分場景。
    static func activeEncounters(count: Int = 50) -> FHIRSearch {
        FHIRSearch(
            resourceType: "Encounter",
            parameters: [
                .init("status", "in-progress"),
                .init("_include", "Encounter:subject"),
                .init("_count", String(count))
            ]
        )
    }

    /// 某位病人的生命徵象，新到舊。
    static func vitalSigns(patientID: String, count: Int = 100) -> FHIRSearch {
        FHIRSearch(
            resourceType: "Observation",
            parameters: [
                .init("patient", patientID),
                .init("category", ObservationCategory.vitalSigns),
                .init("_sort", "-date"),
                .init("_count", String(count))
            ]
        )
    }
}
