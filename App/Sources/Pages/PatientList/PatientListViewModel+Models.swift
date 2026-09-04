import Foundation
import FHIRCore
import FHIRClient

// MARK: - State

extension PatientListViewModel {

  struct State: Equatable, Sendable {
    var isFirstAppear: Bool = true
    var slice: Slice = .all
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

  /// 這份清單顯示哪一群病人。
  ///
  /// 與主畫面的切片一一對應，但各自定義——跨 feature 傳的是字串識別碼，
  /// 兩邊都不必認識對方的型別。
  enum Slice: String, Sendable, CaseIterable {
    case all
    case seenToday
    case outOfRange
    case onMedication

    /// 識別碼來自 app 內部（主畫面切片的 rawValue），不是外部輸入。
    /// 萬一對不上就退回全部病人——顯示全部比顯示空白或崩潰對使用者有用。
    init(identifier: String) {
      self = Slice(rawValue: identifier) ?? .all
    }
  }

  struct Patient: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var gender: PatientGender
    /// FHIR 的 `date` 允許部分精度（只有年、或年月），所以不用 `Date`。
    var birthDate: DateComponents?
    /// 病歷號。取自 `Patient.identifier`，可能沒有。
    var recordNumber: String?

    /// 足歲。生日精度不足到無法判斷時回 `nil`。
    var age: Int? { age(asOf: .now) }

    /// 可注入基準日的版本。`var age` 用當下時間，測試用固定日期——
    /// 否則年齡的斷言會隨執行日期漂移。
    func age(asOf now: Date, calendar: Calendar = .current) -> Int? {
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

// MARK: - 切片 → 查詢與取值

extension PatientListViewModel.Slice {

  /// 與主畫面同一套理由：只有「超出參考值」需要多頁取樣。
  var maxPages: Int {
    switch self {
    case .outOfRange: 3
    case .all, .seenToday, .onMedication: 1
    }
  }

  var search: FHIRSearch {
    switch self {
    case .all: .patients()
    case .seenToday: .encountersToday()
    case .outOfRange: .recentVitalSigns()
    case .onMedication: .activeMedicationRequests()
    }
  }

  /// 從回應中取出這個切片要顯示的病人。
  ///
  /// 除了 `all` 之外，病人都是透過 `_include` 夾帶回來的——查詢的主體是就診、
  /// 用藥或觀測值，病人是附帶的。`outOfRange` 還要多一步：先挑出真正落在
  /// server 提供範圍之外的觀測值，再回頭取它們的病人。
  func patients(from bundle: FHIR.Bundle) -> [FHIR.Patient] {
    let included = bundle.resources(of: FHIR.Patient.self)

    switch self {
    case .all:
      return included

    case .seenToday, .onMedication:
      return included

    case .outOfRange:
      // 與主畫面的計數用同一個時間窗——server 的 date 過濾不能信（實測 Siming 靜默無效）。
      let cutoff = Date().addingTimeInterval(-MainViewModel.SliceCount.outOfRangeWindowHours * 3600)
      let references = Set(
        bundle.resources(of: FHIR.Observation.self)
          .filter { $0.recorded(onOrAfter: cutoff) }
          .filter { $0.referenceRangeStatus == .outside }
          .compactMap { $0.subject?.reference?.value?.string }
      )
      return included.filter { patient in
        guard let id = patient.id?.value?.string else { return false }
        return references.contains("Patient/\(id)")
      }
    }
  }
}
