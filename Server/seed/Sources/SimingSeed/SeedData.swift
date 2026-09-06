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

    /// Practitioner 的**資源 id**（不是 identifier 的值，雖然這裡刻意讓兩者相同）。
    ///
    /// 固定而非由 server 分配：Keycloak 的帳號屬性存的是 `Practitioner/<id>`，
    /// 而 server 分配的 UUID 每次重灌都會變，綁定會失效。
    ///
    /// 只依賴 seq——不查詢 server 就能算出任何一位醫事人員的位址，這正是外部系統
    /// 能長期綁定的前提。
    static func practitionerResourceID(seq: Int) -> String { "practitioner-\(seq)" }

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
        .init(seq: 3, family: "邱", given: "承翰", gender: .male,   birthYear: 1968, birthMonth: 2, birthDay: 14),
        .init(seq: 4, family: "康", given: "雅琳", gender: .female, birthYear: 1990, birthMonth: 11, birthDay: 7)
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
        /// 平穩的走勢，由舊到新。全部落在參考範圍內。
        let steady: [Double]
        /// 惡化中的走勢，由舊到新。最後一到兩點落在參考範圍外。
        ///
        /// 這是趨勢圖存在的理由：38.8 這個數字本身說明不了什麼，
        /// 「從 37.0 一路升到 38.8」才是臨床要看的東西。
        let rising: [Double]
    }

    /// 每位病人的觀測時間點，由舊到新（小時前）。
    ///
    /// 跨越 48 小時是 spec 的要求——少於這個範圍就看不出走勢。
    /// 其中兩點落在近 24 小時內，讓「超出參考值」切片有東西可算。
    static let observationHoursAgo: [Double] = [42, 30, 9, 3]

    static let vitals: [VitalSpec] = [
        .init(code: LOINC.bodyTemperature, display: "體溫", unit: "°C", unitCode: "Cel",
              low: 36.0, high: 37.5,
              steady: [36.6, 36.9, 37.1, 36.8],
              rising: [37.0, 37.6, 38.3, 38.8]),
        .init(code: LOINC.heartRate, display: "心跳速率", unit: "次/分", unitCode: "/min",
              low: 60, high: 100,
              steady: [72, 76, 74, 78],
              rising: [88, 96, 108, 116]),
        .init(code: LOINC.respiratoryRate, display: "呼吸速率", unit: "次/分", unitCode: "/min",
              low: 12, high: 20,
              steady: [14, 15, 16, 15],
              rising: [18, 20, 23, 25]),
        // 血氧刻意不帶參考範圍：即使數值一路下降，app 也不得判定它異常
        .init(code: LOINC.oxygenSaturation, display: "血氧飽和度", unit: "%", unitCode: "%",
              low: nil, high: nil,
              steady: [98, 97, 97, 98],
              rising: [96, 94, 92, 91])
    ]

    /// 今日有就診紀錄的病人。
    ///
    /// 生命徵象每位病人都有（趨勢圖需要），就診紀錄則只有這幾位——
    /// 診所不會每位病人天天回診。
    static let recentPatientSequences = Set(1...8)

    /// 還在診間的病人（Encounter 沒有 `period.end`，status 為 in-progress）。
    ///
    /// 其餘的就診都已結束。全部開放式會讓「今日就診」這個切片對任何時間查詢都命中，
    /// 而且 8 位病人同時在小診所的診間裡本來就不合理。
    static let inProgressPatientSequences = Set([7, 8])

    /// 一次門診的長度（分鐘）。
    static let consultationMinutes: Double = 20

    /// 走勢惡化、最新數值落在參考範圍外的病人。
    static let outOfRangeSequences = Set([2, 5, 7])

    // MARK: - 醫事人員的角色

    /// HL7 的 practitioner-role 碼系統。
    static let practitionerRoleSystem = "http://terminology.hl7.org/CodeSystem/practitioner-role"

    /// 一位醫事人員在機構裡扮演的角色。
    ///
    /// `code` / `codeDisplay` 走 HL7 標準碼與**該碼系統自己的英文名**——display 的語意是
    /// 「這個碼在該系統裡的意思」，塞中文進去等於改寫別人的碼系統。
    /// 人看的中文職稱放 `CodeableConcept.text`，那正是它的用途。
    struct RoleSpec {
        let seq: Int
        let code: String
        let codeDisplay: String
        let text: String
    }

    /// 2 位醫師 + 2 位護理師。小診所的護理人力通常多於醫師，反過來的比例一看就假。
    static let practitionerRoles: [RoleSpec] = [
        .init(seq: 1, code: "doctor", codeDisplay: "Doctor", text: "主治醫師"),
        .init(seq: 2, code: "nurse",  codeDisplay: "Nurse",  text: "護理師"),
        .init(seq: 3, code: "doctor", codeDisplay: "Doctor", text: "主治醫師"),
        .init(seq: 4, code: "nurse",  codeDisplay: "Nurse",  text: "護理師")
    ]

    /// 有處方權的角色碼。
    ///
    /// 護理師不能開處方——輪流指派 requester 時若不看角色，就會出現「護理師開了
    /// 4 張處方」這種一眼看穿的資料。之前三個人在資料上完全同構所以看不出來，
    /// 補上角色之後這個問題才浮現。
    static let prescriberRoleCodes: Set<String> = ["doctor"]

    /// 初診病人：只有最近一次紀錄，沒有可比較的歷史。
    ///
    /// 這種病人在診所裡本來就存在，而且他讓「單一觀測值也要畫得出來」
    /// 不必靠 Preview 才驗得到——在真實資料上就看得見。
    static let firstVisitSequences = Set([20])

    // MARK: - 處方

    /// 一次的量。與觀測值一樣走 UCUM——`{tablet}` 這類註記單位是 UCUM 的合法寫法。
    struct Dose {
        let value: Double
        let unit: String
        let code: String
    }

    /// 一段給藥指示，對應 FHIR 的一筆 `dosageInstruction`。
    struct DosageStep {
        let dose: Dose
        /// 一個週期內給幾次。
        let frequency: Int
        /// 週期長度與單位（FHIR 的 `period` / `periodUnit`）。
        let period: Double
        let periodUnit: String
        /// 明確的給藥時間。
        ///
        /// **空陣列不是「沒有時程」，而是「記錄沒有指定是哪幾點」**——那幾點由機構的
        /// 給藥常規決定，不在 FHIR 資料裡。這個區別正是用藥頁要展示的東西，所以
        /// seed 必須同時提供空的與非空的，否則畫面上分不出實作有沒有搞混。
        let timesOfDay: [(hour: UInt8, minute: UInt8)]
        /// 這一段持續幾天；`nil` 表示記錄未指定期程。
        let days: Int?
    }

    /// 處方的時程形態。四種都刻意選過——簡單的形態證明不了什麼。
    enum DosageShape {
        /// 固定次數但未指定時間。臨床上最常見，也最容易被實作自行填上時間。
        case unspecifiedTimes(DosageStep)
        /// 需要時服用：**沒有時程可言**，不是「時程未知」。
        case asNeeded(reason: String, dose: Dose)
        /// 劑量隨時間遞減，一張處方多段指示，靠 `sequence` 表達順序。
        case tapering([DosageStep])
        /// 記錄有指定時間——對照組，讓「未指定」在同一份資料裡看得出是刻意的。
        case explicitTimes(DosageStep)
    }

    struct MedicationSpec {
        let name: String
        let shape: DosageShape
    }

    private static let tablet = Dose(value: 1, unit: "錠", code: "{tablet}")
    private static let capsule = Dose(value: 1, unit: "膠囊", code: "{capsule}")

    private static func daily(
        _ dose: Dose, times frequency: Int,
        at timesOfDay: [(hour: UInt8, minute: UInt8)] = [], days: Int? = nil
    ) -> DosageStep {
        .init(dose: dose, frequency: frequency, period: 1, periodUnit: "d",
              timesOfDay: timesOfDay, days: days)
    }

    /// 10 張處方，四種時程形態都到齊。
    ///
    /// Prednisolone 是唯一會遞減的一張——類固醇短期療程本來就這樣開。把遞減硬套在
    /// 降血壓或降血糖藥上，資料一眼就假，而這個 repo 的資料必須經得起看。
    static let medications: [MedicationSpec] = [
        .init(name: "Amoxicillin 500mg 膠囊",
              shape: .unspecifiedTimes(daily(capsule, times: 3, days: 7))),
        .init(name: "Metformin 500mg 錠",
              shape: .explicitTimes(daily(tablet, times: 2, at: [(8, 0), (18, 0)]))),
        .init(name: "Amlodipine 5mg 錠",
              shape: .unspecifiedTimes(daily(tablet, times: 1))),
        .init(name: "Prednisolone 5mg 錠",
              shape: .tapering([
                  daily(Dose(value: 4, unit: "錠", code: "{tablet}"), times: 1, days: 3),
                  daily(Dose(value: 2, unit: "錠", code: "{tablet}"), times: 1, days: 3),
                  daily(tablet, times: 1, days: 3)
              ])),
        .init(name: "Losartan 50mg 錠",
              shape: .unspecifiedTimes(daily(tablet, times: 1))),
        .init(name: "Acetaminophen 500mg 錠",
              shape: .asNeeded(reason: "發燒或疼痛", dose: tablet)),
        .init(name: "Omeprazole 20mg 膠囊",
              shape: .unspecifiedTimes(daily(capsule, times: 1))),
        .init(name: "Aspirin 100mg 錠",
              shape: .unspecifiedTimes(daily(tablet, times: 1))),
        .init(name: "Levothyroxine 50mcg 錠",
              shape: .explicitTimes(daily(tablet, times: 1, at: [(7, 0)]))),
        .init(name: "Salbutamol 吸入劑",
              shape: .asNeeded(reason: "喘鳴發作",
                               dose: Dose(value: 2, unit: "吸", code: "{puff}")))
    ]
}
