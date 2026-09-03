import Foundation
import FHIRCore

// MARK: - State

extension MainViewModel {

  struct State: Equatable, Sendable {
    var isFirstAppear: Bool = true
    var practitioner: PractitionerIdentity?
    var slices: [PatientSlice: SliceState] = PatientSlice.initialStates
    /// 目前推進到哪個切片的清單。`nil` 表示停在 grid。
    ///
    /// 由 state 驅動而非 onRoute：這是內容區裡 NavigationStack 的推進，
    /// 不需要取得 presenting VC，照 V 層規範屬於 View 自己做得到的事。
    var presentedSlice: PatientSlice?
    /// 顯示在側邊欄底部，讓使用者知道自己連到哪裡。
    var serverHost: String = ""

    /// 供 grid 依固定順序呈現。
    var sliceCards: [SliceCard] {
      PatientSlice.allCases.map { SliceCard(slice: $0, state: slices[$0] ?? .init()) }
    }
  }

  struct SliceCard: Identifiable, Equatable, Sendable {
    let slice: PatientSlice
    let state: SliceState

    var id: String { slice.rawValue }
  }

  struct SliceState: Equatable, Sendable {
    var count: SliceCount?
    var status: Status = .prepare
  }

  enum Status: Equatable, Sendable {
    case prepare
    case loading
    case success
    /// 這個切片的計數取不到。卡片仍可點擊——清單本身未必也失敗。
    case unavailable
  }

  /// 側邊欄的大分類。
  ///
  /// 純 UI 狀態：伺服器不知道它存在，也不會出現在任何 API 合約裡。
  /// 目前只有一項，其餘等真的要實作時再加——列佔位項只會讓畫面顯得半成品。
  enum Category: String, Identifiable, CaseIterable, Sendable {
    case patients

    var id: String { rawValue }
  }

  /// 同一群病人的不同切片。
  ///
  /// 不是資料類型——臨床動線永遠是先有病人、再看該病人的資料，所以每個切片
  /// 的終點都是病人清單，不會走進死路。
  enum PatientSlice: String, Identifiable, CaseIterable, Sendable {
    case all
    case seenToday
    case outOfRange
    case onMedication

    var id: String { rawValue }

    static var initialStates: [PatientSlice: SliceState] {
      Dictionary(uniqueKeysWithValues: allCases.map { ($0, SliceState()) })
    }
  }
}

// MARK: - Domain Models

extension MainViewModel {

  /// 一個切片的病人數。
  ///
  /// 區分精確與下限是必要的：server 未必回傳 `Bundle.total`（HAPI 公開 server 實測就不回），
  /// 而取樣有上限。此時撈到幾筆只能當下限——把它當成總數會把 38 位病人報成 2 位。
  enum SliceCount: Equatable, Sendable {
    case exact(Int)
    case atLeast(Int)

    var amount: Int {
      switch self {
      case let .exact(value), let .atLeast(value): value
      }
    }

    var isLowerBound: Bool {
      if case .atLeast = self { return true }
      return false
    }
  }

  /// 登入者的身分。
  struct PractitionerIdentity: Equatable, Sendable {
    /// 形如 `Practitioner/137594487`，一定有——它來自 id_token。
    let reference: String
    /// 從 Practitioner 資源解出的姓名。server 資料品質差時可能沒有。
    var name: String?
    /// 從 PractitionerRole 解出的職位顯示文字。
    var role: String?

    /// 姓名取不到時退回 reference——空白的 header 比顯示原始 reference 更糟。
    var displayName: String { name ?? reference }
  }
}

// MARK: - DTOs

extension MainViewModel {

  /// 身分解析的兩支查詢結果。兩支都可能失敗或回傳無用資料。
  struct IdentityPayload: Sendable {
    let practitioner: FHIR.Practitioner?
    let roles: [FHIR.PractitionerRole]
  }
}

extension MainViewModel.PractitionerIdentity {

  init(reference: String, payload: MainViewModel.IdentityPayload) {
    self.reference = reference
    self.name = payload.practitioner?.name?.firstDisplayText
    self.role = payload.roles
      .compactMap { role in
        role.code?.compactMap { $0.coding?.compactMap { $0.display?.value?.string }.first }.first
      }
      .first
  }
}

extension MainViewModel.SliceCount {

  /// 從 bundle 算出切片的**病人數**。
  ///
  /// 三個切片都必須依 subject 去重——一位病人可能有多次就診、多筆用藥、多筆觀測值，
  /// 而卡片說的是「幾位病人」不是「幾筆紀錄」。
  static func make(from response: FHIRBundleDecoder.Result, slice: MainViewModel.PatientSlice) -> Self {
    let bundle = response.bundle
    // 有 entry 被跳過就不能宣稱精確——數字必然少算，只是不知道少多少。
    let hasMore = bundle.nextPageURL != nil || response.isPartial

    switch slice {
    case .all:
      // 病人清單本身就是一筆一位，能拿到 total 就是精確值。
      // total 是 server 對自己資料的陳述，與本地解碼成敗無關——不因跳過而降級。
      if let total = bundle.searchTotal {
        return .exact(total)
      }
      let count = bundle.resources(of: FHIR.Patient.self).count
      return hasMore ? .atLeast(count) : .exact(count)

    case .seenToday:
      return count(of: bundle.resources(of: FHIR.Encounter.self).map(\.subject), hasMore: hasMore)

    case .onMedication:
      return count(of: bundle.resources(of: FHIR.MedicationRequest.self).map { $0.subject }, hasMore: hasMore)

    case .outOfRange:
      // 只計入 server 有給參考範圍、且數值落在範圍外的。沒給範圍不判讀。
      let subjects = bundle.resources(of: FHIR.Observation.self)
        .filter { $0.referenceRangeStatus == .outside }
        .map(\.subject)
      return count(of: subjects, hasMore: hasMore)
    }
  }

  private static func count(of subjects: [FHIR.Reference?], hasMore: Bool) -> Self {
    let patients = Set(subjects.compactMap { $0?.reference?.value?.string })
    return hasMore ? .atLeast(patients.count) : .exact(patients.count)
  }
}
