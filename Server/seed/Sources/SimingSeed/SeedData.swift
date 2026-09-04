import Foundation
import FHIRCore
import ModelsR4
import TWCoreFHIRModels

/// 示範資料的定義。
///
/// 目標是「看起來像台灣診所的紀錄」，不是壓測——資料一旦看起來假，
/// demo 的對話就會停在資料上，走不到產品本身。
enum SeedData {

    /// 所有 seed 資源共用的 identifier system，冪等的依據。
    static let identifierSystem = "urn:tideng:demo"
    /// 病歷號的 system。
    static let recordNumberSystem = "urn:oid:2.16.886.101.20003.20001.1"

    static let timeZone = TimeZone(identifier: "Asia/Taipei")!

    // MARK: - 人

    struct PersonSpec {
        let seq: Int
        let family: String
        let given: String
        let gender: AdministrativeGender
        let birthYear: Int
        let birthMonth: Int
        let birthDay: Int
    }

    /// 20 位病人。年齡分布刻意涵蓋青壯年到高齡——診所的病人組成本來就是這樣。
    static let patients: [PersonSpec] = [
        .init(seq: 1,  family: "王", given: "志明", gender: .male,   birthYear: 1958, birthMonth: 3,  birthDay: 14),
        .init(seq: 2,  family: "陳", given: "淑芬", gender: .female, birthYear: 1972, birthMonth: 11, birthDay: 2),
        .init(seq: 3,  family: "林", given: "建宏", gender: .male,   birthYear: 1945, birthMonth: 6,  birthDay: 20),
        .init(seq: 4,  family: "黃", given: "美玲", gender: .female, birthYear: 1989, birthMonth: 1,  birthDay: 8),
        .init(seq: 5,  family: "張", given: "雅婷", gender: .female, birthYear: 1995, birthMonth: 7,  birthDay: 23),
        .init(seq: 6,  family: "李", given: "文雄", gender: .male,   birthYear: 1951, birthMonth: 9,  birthDay: 5),
        .init(seq: 7,  family: "吳", given: "秀英", gender: .female, birthYear: 1938, birthMonth: 4,  birthDay: 17),
        .init(seq: 8,  family: "劉", given: "俊傑", gender: .male,   birthYear: 1980, birthMonth: 12, birthDay: 30),
        .init(seq: 9,  family: "蔡", given: "佳蓉", gender: .female, birthYear: 2001, birthMonth: 2,  birthDay: 11),
        .init(seq: 10, family: "鄭", given: "國強", gender: .male,   birthYear: 1966, birthMonth: 8,  birthDay: 25),
        .init(seq: 11, family: "謝", given: "雅琪", gender: .female, birthYear: 1993, birthMonth: 5,  birthDay: 3),
        .init(seq: 12, family: "許", given: "志偉", gender: .male,   birthYear: 1975, birthMonth: 10, birthDay: 19),
        .init(seq: 13, family: "洪", given: "淑惠", gender: .female, birthYear: 1948, birthMonth: 1,  birthDay: 27),
        .init(seq: 14, family: "曾", given: "建良", gender: .male,   birthYear: 1962, birthMonth: 6,  birthDay: 9),
        .init(seq: 15, family: "廖", given: "美惠", gender: .female, birthYear: 1984, birthMonth: 3,  birthDay: 15),
        .init(seq: 16, family: "賴", given: "宗翰", gender: .male,   birthYear: 1998, birthMonth: 11, birthDay: 21),
        .init(seq: 17, family: "周", given: "淑貞", gender: .female, birthYear: 1955, birthMonth: 7,  birthDay: 6),
        .init(seq: 18, family: "徐", given: "銘傑", gender: .male,   birthYear: 1970, birthMonth: 2,  birthDay: 28),
        .init(seq: 19, family: "蕭", given: "麗華", gender: .female, birthYear: 1941, birthMonth: 9,  birthDay: 12),
        .init(seq: 20, family: "潘", given: "冠宇", gender: .male,   birthYear: 2005, birthMonth: 4,  birthDay: 1)
    ]

    static let practitioners: [PersonSpec] = [
        .init(seq: 1, family: "何", given: "宗霖", gender: .male,   birthYear: 1975, birthMonth: 5, birthDay: 10),
        .init(seq: 2, family: "簡", given: "怡君", gender: .female, birthYear: 1982, birthMonth: 8, birthDay: 22),
        .init(seq: 3, family: "邱", given: "承翰", gender: .male,   birthYear: 1968, birthMonth: 2, birthDay: 14)
    ]

    // MARK: - 生命徵象的種類

    struct VitalSpec {
        let code: String
        let display: String
        let unit: String
        let unitCode: String
        /// server 提供的參考範圍。`nil` 表示刻意不給——用來示範 app 不對沒有依據的數值做判斷。
        let low: Double?
        let high: Double?
        /// 正常範圍內的取值
        let normal: ClosedRange<Double>
        /// 刻意落在範圍外的取值
        let abnormal: ClosedRange<Double>
    }

    static let vitals: [VitalSpec] = [
        .init(code: LOINC.bodyTemperature, display: "體溫", unit: "°C", unitCode: "Cel",
              low: 36.0, high: 37.5, normal: 36.2...37.2, abnormal: 38.2...39.4),
        .init(code: LOINC.heartRate, display: "心跳速率", unit: "次/分", unitCode: "/min",
              low: 60, high: 100, normal: 66...92, abnormal: 104...126),
        .init(code: LOINC.respiratoryRate, display: "呼吸速率", unit: "次/分", unitCode: "/min",
              low: 12, high: 20, normal: 13...19, abnormal: 22...27),
        // 血氧刻意不帶參考範圍：即使數值偏低，app 也不得判定它異常
        .init(code: LOINC.oxygenSaturation, display: "血氧飽和度", unit: "%", unitCode: "%",
              low: nil, high: nil, normal: 95...99, abnormal: 89...93)
    ]

    /// 有近 24 小時觀測值的病人（對應「今日就診」）。
    ///
    /// 只有 8 位是刻意的：近 24 小時的觀測值總數必須低於 Siming 的 `_count` 上限 100，
    /// 否則查詢會被靜默截斷、計數安靜地低估。8 × 2 個時間點 × 4 種 = 64 筆。
    static let recentPatientSequences = Set(1...8)

    /// 觀測值落在參考範圍外的病人。
    static let outOfRangeSequences = Set([2, 5, 7])
}
