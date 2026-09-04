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

// MARK: - 主畫面切片需要的查詢

public extension FHIRSearch {

    /// 某位 practitioner 的角色。用來取得職位顯示文字。
    static func practitionerRoles(practitionerID: String) -> FHIRSearch {
        FHIRSearch(
            resourceType: "PractitionerRole",
            parameters: [.init("practitioner", practitionerID)]
        )
    }

    /// 今天（含）以後的就診，並帶回病人本身。
    ///
    /// 「今天」以**裝置所在時區的當地日期**為準——診所關心的是自己的一天，不是 UTC 的一天。
    /// `now` 與 `calendar` 可注入，否則測試會隨執行時間與機器時區飄移。
    static func encountersToday(
        now: Date = .now,
        calendar: Calendar = .current,
        count: Int = 200
    ) -> FHIRSearch {
        FHIRSearch(
            resourceType: "Encounter",
            parameters: [
                .init("date", "ge\(Self.localDate(now, calendar: calendar))"),
                .init("_include", "Encounter:subject"),
                .init("_count", String(count))
            ]
        )
    }

    /// 進行中的用藥請求，並帶回病人本身。
    ///
    /// `_include` 是為了讓病人清單能直接顯示 Patient；計數只需要 subject reference，
    /// 但 `_include` 的資源不計入 `_count`（FHIR 規定 `_count` 只算 match），
    /// 所以兩種用途可以共用同一條查詢。
    static func activeMedicationRequests(count: Int = 200) -> FHIRSearch {
        FHIRSearch(
            resourceType: "MedicationRequest",
            parameters: [
                .init("status", "active"),
                .init("_include", "MedicationRequest:subject"),
                .init("_count", String(count))
            ]
        )
    }

    /// 近期的生命徵象。
    ///
    /// FHIR 沒有針對 referenceRange 的 search parameter，所以「超出參考值」只能把資料撈回來
    /// 在 client 端比對。時間窗與 `_count` 是那個做法的必要邊界——沒有它們，資料量大的
    /// server 會讓這個查詢無止境地長大。
    ///
    /// 上限 100 是對齊 Siming 的實際能力：它的 route 檔硬寫 `maxCount = 100`，
    /// 送更大的值會被**靜默截斷**——查詢不報錯，只是資料少一截、計數安靜地低估。
    /// （`config.yml` 裡宣稱的 `maxCount: 1000` 是死設定，`SimingConfig` 沒有這個欄位。）
    static func recentVitalSigns(
        now: Date = .now,
        hours: Int = 24,
        count: Int = 100
    ) -> FHIRSearch {
        let since = now.addingTimeInterval(-Double(hours) * 3600)
        return FHIRSearch(
            resourceType: "Observation",
            parameters: [
                .init("category", ObservationCategory.vitalSigns),
                .init("date", "ge\(Self.instant(since))"),
                .init("_include", "Observation:subject"),
                .init("_count", String(count))
            ]
        )
    }

    // MARK: - 日期格式

    /// FHIR `date` 精度（YYYY-MM-DD），以指定曆法的時區解讀。
    private static func localDate(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// FHIR `instant` 精度，一律 UTC。
    private static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
