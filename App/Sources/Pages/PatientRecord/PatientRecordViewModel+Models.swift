import Foundation
import FHIRCore

// MARK: - State

extension PatientRecordViewModel {

  struct State: Equatable, Sendable {
    var isFirstAppear: Bool = true
    /// 由清單傳入，不重查——清單已經有這些資料，重查只會讓標題先空白再填上。
    var patient: PatientIdentity
    /// 從 server 取回的完整記錄。清單那一層看不到 identifier 陣列的全貌，
    /// 所以身分證號只能在這裡才拿得到。
    var record: Record?
    var api: API = .init()
  }

  struct API: Equatable, Sendable {
    var loadRecord: Status = .prepare
  }

  enum Status: Equatable, Sendable {
    case prepare
    case loading
    case success
    case error(message: String)
  }
}

// MARK: - Domain Models

extension PatientRecordViewModel {

  /// 病人的身分資料。全部是 primitive，跨 feature 邊界時原樣傳遞。
  struct PatientIdentity: Equatable, Sendable {
    let id: String
    let name: String
  }

  /// FHIR `Patient` resource 上實際記著的東西。
  ///
  /// 每一個欄位都是 optional，而且 `nil` 一律代表「記錄沒有這一項」——不是
  /// 「還沒載入」也不是「載入失敗」。UI 據此整行省略，不填佔位字串。
  struct Record: Equatable, Sendable {
    let name: String?
    /// `nil` 表示 resource 沒有 `gender` 欄位。`.unknown` 是 FHIR 的合法值，
    /// 意思是「記錄過，而記的是不詳」——兩者不同，所以不能合併。
    let gender: Gender?
    /// FHIR 的 `date` 允許部分精度（只有年、或年月），所以不用 `Date`。
    let birthDate: DateComponents?
    /// 只採用標記為 MR 的 identifier。辨識不出用途的一律不顯示。
    let recordNumber: String?
    let nationalIdentifier: String?

    /// 足歲。生日精度不足到無法判斷時回 `nil`，UI 連同生日一起省略。
    func age(asOf now: Date = .now, calendar: Calendar = .current) -> Int? {
      guard let birthDate, let year = birthDate.year else { return nil }
      let today = calendar.dateComponents([.year, .month, .day], from: now)
      guard let thisYear = today.year else { return nil }

      var age = thisYear - year
      // 只有年份時無法判斷生日過了沒，直接回年份差。
      if let month = birthDate.month, let todayMonth = today.month {
        if todayMonth < month {
          age -= 1
        } else if todayMonth == month, let day = birthDate.day, let todayDay = today.day, todayDay < day {
          age -= 1
        }
      }
      return age >= 0 ? age : nil
    }
  }

  /// L2：只被 `Record` 使用。對齊 FHIR 的 `AdministrativeGender` value set。
  enum Gender: Sendable {
    case male
    case female
    case other
    case unknown
  }
}

// MARK: - DTOs

// FHIR 的 `Patient` resource 就是本 feature 的 DTO。轉換寫在 Domain Model 這一側，
// 掛在 FHIRModels 型別上會外洩給同 module 的其他 feature。
extension PatientRecordViewModel.Record {

  init(resource: FHIR.Patient) {
    self.name = resource.name?.firstDisplayText
    self.gender = resource.gender?.value.map(PatientRecordViewModel.Gender.init)
    self.birthDate = resource.birthDate?.value.map {
      DateComponents(
        year: Int($0.year),
        month: $0.month.map(Int.init),
        day: $0.day.map(Int.init)
      )
    }
    // 兩者都只認得出型別的那一個。認不出來的 identifier 一律不顯示——
    // 一個沒有標籤的號碼會讓讀的人自己假設它是他認得的那一個。
    self.recordNumber = resource.identifier?.medicalRecordNumber
    self.nationalIdentifier = resource.identifier?.nationalIdentificationNumber
  }
}

extension PatientRecordViewModel.Gender {

  init(_ gender: FHIR.AdministrativeGender) {
    switch gender {
    case .male: self = .male
    case .female: self = .female
    case .other: self = .other
    case .unknown: self = .unknown
    }
  }
}
