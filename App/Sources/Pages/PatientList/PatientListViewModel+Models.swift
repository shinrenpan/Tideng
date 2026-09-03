import Foundation
import FHIRCore

// MARK: - State

extension PatientListViewModel {

  struct State: Equatable, Sendable {
    var isFirstAppear: Bool = true
    var patients: [Patient] = []
    var keyword: String = ""
    var api: API = .init()

    var filteredPatients: [Patient] {
      guard !keyword.isEmpty else { return patients }
      return patients.filter {
        $0.name.localizedCaseInsensitiveContains(keyword)
          || ($0.recordNumber?.localizedCaseInsensitiveContains(keyword) ?? false)
      }
    }
  }

  struct API: Equatable, Sendable {
    var loadPatients: Status = .prepare
  }

  enum Status: Equatable, Sendable {
    case prepare
    case loading
    case success
    case error(message: String)
  }
}

// MARK: - Domain Models

extension PatientListViewModel {

  struct Patient: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var gender: PatientGender
    /// FHIR 的 `date` 允許部分精度（只有年、或年月），所以不用 `Date`。
    var birthDate: DateComponents?
    /// 病歷號。取自 `Patient.identifier`，可能沒有。
    var recordNumber: String?

    /// 足歲。生日精度不足到無法判斷時回 `nil`。
    var age: Int? {
      guard let birthDate, let year = birthDate.year else { return nil }
      let today = Calendar.current.dateComponents([.year, .month, .day], from: .now)
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

  /// L2：只被 `Patient` 使用。
  ///
  /// 對齊 FHIR 的 `AdministrativeGender` value set——這是 API 合約的一部分，不是 UI 狀態。
  enum PatientGender: Sendable {
    case male
    case female
    case other
    case unknown
  }
}

// MARK: - DTOs

// FHIR 的 `Patient` resource 就是本 feature 的 DTO：它已忠實對應 R4 wire format，
// 再包一層自己的解碼結構只是重複勞動。
//
// 但它是 FHIRModels 的型別，把 `toDomain()` 掛在它身上會外洩給同 module 的其他 feature
// （違反「Domain Model 不跨 feature」），所以轉換寫在 Domain Model 這一側。
extension PatientListViewModel.Patient {

  init?(resource: FHIR.Patient) {
    guard let id = resource.id?.value?.string else { return nil }

    self.id = id
    self.name = resource.name?.firstDisplayText ?? String(localized: "Unnamed")
    self.gender = .init(resource.gender?.value)
    self.birthDate = resource.birthDate?.value.map {
      DateComponents(
        year: Int($0.year),
        month: $0.month.map(Int.init),
        day: $0.day.map(Int.init)
      )
    }
    self.recordNumber = resource.identifier?
      .compactMap { $0.value?.value?.string }
      .first
  }

}

extension PatientListViewModel.PatientGender {

  init(_ gender: FHIR.AdministrativeGender?) {
    switch gender {
    case .male: self = .male
    case .female: self = .female
    case .other: self = .other
    case .unknown, .none: self = .unknown
    }
  }
}
