import Foundation
import FHIRCore

// MARK: - State

extension PatientEncountersViewModel {

  struct State: Equatable, Sendable {
    var isFirstAppear: Bool = true
    var patient: PatientIdentity
    var encounters: [Encounter] = []
    var api: API = .init()
  }

  struct API: Equatable, Sendable {
    var loadEncounters: Status = .prepare
  }

  enum Status: Equatable, Sendable {
    case prepare
    case loading
    case success
    case error(message: String)
  }
}

// MARK: - Domain Models

extension PatientEncountersViewModel {

  struct PatientIdentity: Equatable, Sendable {
    let id: String
    let name: String
  }

  /// 一次就診。
  ///
  /// `status` 與 `period` 是**兩個獨立的事實**，可能互相矛盾（status 說 finished
  /// 但 period 沒有 end 是完全合法的資料）。這個型別刻意不把兩者調和成一個
  /// 「真正的狀態」——調和就是替記錄做決定。
  struct Encounter: Identifiable, Equatable, Sendable {
    let id: String
    /// 記錄的 status，原樣帶著。
    let status: VisitStatus
    /// `class` 的顯示文字，取 display，沒有就取 code。兩者都沒有就 `nil`。
    let classDisplay: String?
    let startedAt: Date?
    let endedAt: Date?
    let participants: [Participant]

    /// 有開始、沒有結束：FHIR 的意思是「還沒結束，或結束時間沒被記下來」。
    ///
    /// 這**不是**「進行中」的同義詞——`status` 才是狀態。這裡說的只是 period 這個
    /// 欄位的形狀。畫面不得以當下時間替代缺少的 end。
    var hasOpenPeriod: Bool { startedAt != nil && endedAt == nil }

    /// 完全沒有 period：既不能說何時開始，也不能宣稱它還開著。
    var hasNoPeriod: Bool { startedAt == nil && endedAt == nil }
  }

  /// L2：只被 `Encounter` 使用。對齊 FHIR 的 `EncounterStatus` value set。
  ///
  /// `other` 保留 server 送來的原始碼——遇到不認得的值就照著顯示，比顯示
  /// 「未知」誠實：那個碼是記錄的一部分。
  enum VisitStatus: Equatable, Sendable {
    case planned
    case arrived
    case triaged
    case inProgress
    case onleave
    case finished
    case cancelled
    case enteredInError
    case unknown
    case other(String)
  }

  /// 就診的參與者。
  struct Participant: Identifiable, Equatable, Sendable {
    /// reference 字串本身。解析不到姓名時它就是畫面上顯示的東西。
    let id: String
    /// 解析到的姓名。`nil` 表示 server 沒把這個 practitioner 一併回傳。
    let name: String?
  }
}

// MARK: - DTOs

extension PatientEncountersViewModel.Encounter {

  /// - Parameter practitioners: reference（`Practitioner/<id>`）對應到姓名。
  ///   由 `_include` 帶回的資源建立；查不到的就留在 reference 形式。
  init?(resource: FHIR.Encounter, practitioners: [String: String]) {
    guard let id = resource.id?.value?.string else { return nil }

    self.id = id
    self.status = .init(resource.status.value)
    self.classDisplay = resource.class.display?.value?.string
      ?? resource.class.code?.value?.string
    self.startedAt = try? resource.period?.start?.value?.asNSDate()
    self.endedAt = try? resource.period?.end?.value?.asNSDate()
    self.participants = (resource.participant ?? []).compactMap { participant in
      guard let reference = participant.individual?.reference?.value?.string else { return nil }
      return .init(id: reference, name: practitioners[reference])
    }
  }
}

extension PatientEncountersViewModel.VisitStatus {

  init(_ status: FHIR.EncounterStatus?) {
    switch status {
    case .planned: self = .planned
    case .arrived: self = .arrived
    case .triaged: self = .triaged
    case .inProgress: self = .inProgress
    case .onleave: self = .onleave
    case .finished: self = .finished
    case .cancelled: self = .cancelled
    case .enteredInError: self = .enteredInError
    case .unknown, .none: self = .unknown
    }
  }
}

extension PatientEncountersViewModel {

  /// 把一份回應整理成畫面要的就診清單。
  ///
  /// 排序在這裡完成，View 不負責排序。**不依賴 server 的 `_sort`**：它只認少數
  /// 欄位，未知欄位靜默丟棄——那會讓「有沒有排序」變成看不見的差異。
  ///
  /// 沒有 period 的就診排在最後：它們沒有可比較的時間，硬塞進時間序等於替它們
  /// 編一個時間。
  static func encounters(from bundle: FHIR.Bundle) -> [Encounter] {
    let practitioners = Dictionary(
      bundle.resources(of: FHIR.Practitioner.self).compactMap { practitioner -> (String, String)? in
        guard let id = practitioner.id?.value?.string,
              let name = practitioner.name?.firstDisplayText
        else { return nil }
        return ("Practitioner/\(id)", name)
      },
      uniquingKeysWith: { first, _ in first }
    )

    return bundle.resources(of: FHIR.Encounter.self)
      .compactMap { Encounter(resource: $0, practitioners: practitioners) }
      .sorted { left, right in
        switch (left.startedAt, right.startedAt) {
        case let (l?, r?): l > r
        case (nil, _?): false
        case (_?, nil): true
        case (nil, nil): left.id < right.id
        }
      }
  }
}
