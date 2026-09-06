import Foundation
import FHIRCore

// MARK: - State

extension PatientMedicationsViewModel {

  struct State: Equatable, Sendable {
    var isFirstAppear: Bool = true
    var patient: PatientIdentity
    var prescriptions: [Prescription] = []
    var api: API = .init()
  }

  struct API: Equatable, Sendable {
    var loadPrescriptions: Status = .prepare
  }

  enum Status: Equatable, Sendable {
    case prepare
    case loading
    case success
    case error(message: String)
  }
}

// MARK: - Domain Models

extension PatientMedicationsViewModel {

  struct PatientIdentity: Equatable, Sendable {
    let id: String
    let name: String
  }

  /// 一張處方。
  struct Prescription: Identifiable, Equatable, Sendable {
    let id: String
    /// 藥品名稱，取自記錄。取不到就是 `nil`——不以 id 或其他欄位頂替。
    let medication: String?
    let status: RequestStatus
    /// 開立者。解析不到姓名時退回 reference 本身。
    let requester: Requester?
    let authoredOn: Date?
    /// 每一段 `dosageInstruction`，**順序與記錄一致**。
    ///
    /// 多段是「劑量隨時間改變」的表達方式，合併成一段就把它存在的理由抹掉了。
    let dosages: [DosageLine]
  }

  struct Requester: Equatable, Sendable {
    /// reference 字串。解析不到姓名時它就是畫面上顯示的東西。
    let reference: String
    let name: String?
  }

  /// L2：只被 `Prescription` 使用。對齊 FHIR 的 `MedicationrequestStatus`。
  enum RequestStatus: Equatable, Sendable {
    case active
    case onHold
    case cancelled
    case completed
    case enteredInError
    case stopped
    case draft
    case unknown
    case other(String)
  }

  /// 一段給藥指示。
  struct DosageLine: Identifiable, Equatable, Sendable {
    let id: String
    /// 一次的量，例如「1 錠」。記錄沒寫就是 `nil`。
    let dose: Dose?
    /// 時程。`nil` 表示這一段既沒有 timing 也沒有 asNeeded——記錄真的沒有說。
    let schedule: Schedule?
  }

  struct Dose: Equatable, Sendable {
    let value: Double
    /// server 提供的單位文字。**不從藥品反推**——單位說的是「這個數字是什麼」。
    let unit: String?
  }

  /// 記錄對「什麼時候給」說了什麼。
  ///
  /// 這個型別的四個 case 是本頁的核心判斷。最要緊的是 `frequency` 與 `atTimes`
  /// 的分野：**「一天三次」沒有說是哪三次**。那三個時間點由機構的給藥常規決定，
  /// 不存在於 FHIR 資料裡，所以不得由 app 產生。
  enum Schedule: Equatable, Sendable {
    /// 記錄指定了時間。這些時間在記錄裡，照著顯示。
    case atTimes([TimeOfDay])
    /// 有次數與週期，但**沒有**指定是哪幾點。
    case frequency(count: Int, period: Double, unit: PeriodUnit)
    /// 需要時服用：沒有時程可言，不是「時程未知」。
    case asNeeded(reason: String?)
    /// 有 timing 但結構讀不出來。
    ///
    /// 顯示為「未指定」而不是留白——留白會被讀成「沒有時程」，那與
    /// 「有時程但我們看不懂」是不同的事。
    case unreadable

    /// 記錄有沒有講出具體時間。`false` 時畫面必須明說未指定，不得自行填補。
    var statesClockTimes: Bool {
      if case .atTimes(let times) = self { !times.isEmpty } else { false }
    }
  }

  struct TimeOfDay: Equatable, Hashable, Sendable {
    let hour: Int
    let minute: Int
  }

  /// FHIR `UnitsOfTime` 的週期單位。認不得的碼原樣保留。
  enum PeriodUnit: Equatable, Sendable {
    case second
    case minute
    case hour
    case day
    case week
    case month
    case year
    case other(String)

    init(_ code: String?) {
      switch code {
      case "s": self = .second
      case "min": self = .minute
      case "h": self = .hour
      case "d": self = .day
      case "wk": self = .week
      case "mo": self = .month
      case "a": self = .year
      case let code?: self = .other(code)
      case nil: self = .other("")
      }
    }
  }
}

// MARK: - DTOs

extension PatientMedicationsViewModel.Prescription {

  /// - Parameter practitioners: reference（`Practitioner/<id>`）對應到姓名。
  init?(resource: FHIR.MedicationRequest, practitioners: [String: String]) {
    guard let id = resource.id?.value?.string else { return nil }

    self.id = id
    self.medication = switch resource.medication {
    case let .codeableConcept(concept): concept.displayText
    // 藥品以 reference 表示時，這一頁沒有把它解出來（需要另一次查詢）。
    // 顯示 reference 本身而不是留白——它指得出是哪一筆記錄。
    case let .reference(reference): reference.reference?.value?.string
    }
    self.status = .init(resource.status.value)
    if let reference = resource.requester?.reference?.value?.string {
      self.requester = .init(reference: reference, name: practitioners[reference])
    } else {
      self.requester = nil
    }
    self.authoredOn = try? resource.authoredOn?.value?.asNSDate()
    // 順序照記錄給的，不重排也不合併。
    self.dosages = (resource.dosageInstruction ?? []).enumerated().map { index, dosage in
      PatientMedicationsViewModel.DosageLine(
        id: "\(id)-\(index)",
        dose: PatientMedicationsViewModel.Dose(dosage: dosage),
        schedule: PatientMedicationsViewModel.Schedule(dosage: dosage)
      )
    }
  }
}

extension PatientMedicationsViewModel.Dose {

  init?(dosage: FHIR.Dosage) {
    // 只取第一組 doseAndRate：多組是「劑量或速率有多種表達」，不是多個劑量。
    guard case let .quantity(quantity)? = dosage.doseAndRate?.first?.dose,
          let value = quantity.value?.value?.decimal
    else { return nil }

    self.value = NSDecimalNumber(decimal: value).doubleValue
    self.unit = quantity.unit?.value?.string
  }
}

extension PatientMedicationsViewModel.Schedule {

  /// 判斷順序有意義：
  ///
  /// 1. `asNeeded` 先看——需要時服用**沒有時程**，即使同一筆也帶了 timing，
  ///    「需要時」仍然是它真正說的事。
  /// 2. 有 `timeOfDay` → 記錄講了具體時間，照著顯示。
  /// 3. 有 frequency／period → 記錄講了次數，但**沒講是哪幾點**。
  /// 4. 有 timing 卻讀不出以上任何一種 → 未指定，不是留白。
  init?(dosage: FHIR.Dosage) {
    if let asNeeded = dosage.asNeeded {
      self = switch asNeeded {
      case let .boolean(flag): flag.value?.bool == true ? .asNeeded(reason: nil) : .unreadable
      case let .codeableConcept(concept): .asNeeded(reason: concept.displayText)
      }
      return
    }

    guard let timing = dosage.timing else { return nil }
    guard let repeats = timing.repeat else {
      self = .unreadable
      return
    }

    if let times = repeats.timeOfDay?.compactMap(\.value), !times.isEmpty {
      self = .atTimes(times.map { .init(hour: Int($0.hour), minute: Int($0.minute)) })
      return
    }

    if let frequency = repeats.frequency?.value?.integer, let period = repeats.period?.value?.decimal {
      self = .frequency(
        count: Int(frequency),
        period: NSDecimalNumber(decimal: period).doubleValue,
        unit: .init(repeats.periodUnit?.value?.string)
      )
      return
    }

    self = .unreadable
  }
}

extension PatientMedicationsViewModel.RequestStatus {

  init(_ status: FHIR.MedicationRequestStatus?) {
    switch status {
    case .active: self = .active
    case .onHold: self = .onHold
    case .cancelled: self = .cancelled
    case .completed: self = .completed
    case .enteredInError: self = .enteredInError
    case .stopped: self = .stopped
    case .draft: self = .draft
    case .unknown, .none: self = .unknown
    }
  }
}

extension PatientMedicationsViewModel {

  /// 把一份回應整理成畫面要的處方清單。
  ///
  /// 排序在這裡完成、依開立時間新到舊，View 不負責排序。沒有 `authoredOn` 的排在
  /// 最後——沒有時間就沒有位置可言，硬塞進時間序等於替它編一個時間。
  static func prescriptions(from bundle: FHIR.Bundle) -> [Prescription] {
    let practitioners = Dictionary(
      bundle.resources(of: FHIR.Practitioner.self).compactMap { practitioner -> (String, String)? in
        guard let id = practitioner.id?.value?.string,
              let name = practitioner.name?.firstDisplayText
        else { return nil }
        return ("Practitioner/\(id)", name)
      },
      uniquingKeysWith: { first, _ in first }
    )

    return bundle.resources(of: FHIR.MedicationRequest.self)
      .compactMap { Prescription(resource: $0, practitioners: practitioners) }
      .sorted { left, right in
        switch (left.authoredOn, right.authoredOn) {
        case let (l?, r?): l > r
        case (nil, _?): false
        case (_?, nil): true
        case (nil, nil): left.id < right.id
        }
      }
  }
}

// MARK: - 時程的文字

// 這一段刻意**不**放在 View 的 private display helper 裡，儘管它產生的是顯示文字。
//
// 理由是它不是顯示決策（該用什麼圖示、什麼顏色），而是「把記錄說的話原樣說出來」——
// 而「有沒有多說記錄沒說的事」是這一頁唯一真正要守住的性質，必須測得到。
// private helper 測不到，而測不到的紅線等於沒有紅線。

extension PatientMedicationsViewModel.Schedule {

  /// 時程本身的文字。
  ///
  /// `frequency` 這一支只說次數與週期，**不產生任何時間點**。「一天三次」是一句
  /// 完整而合法的醫囑，它沒有說是哪三次——那由機構的給藥常規決定，不在 FHIR 資料裡。
  var text: String {
    switch self {
    case let .atTimes(times):
      // 記錄裡就是這些時間，照著列。格式沿用 FHIR `time` 的寫法。
      times.map(\.text).joined(separator: ", ")

    case let .frequency(count, period, unit):
      String(localized: "\(count) times per \(unit.periodText(count: period))")

    case let .asNeeded(reason):
      if let reason {
        String(localized: "As needed: \(reason)")
      } else {
        String(localized: "As needed")
      }

    case .unreadable:
      String(localized: "The schedule on this record could not be read.")
    }
  }

  /// 需要補充說明「記錄沒有指定時間」時要顯示的那一句；不需要時為 `nil`。
  ///
  /// 只陳述記錄的狀態。**不得寫成要求使用者採取行動**——「需確認給藥時間」之類的
  /// 說法會把一句事實變成一項指示，而那項指示不是這個 app 能下的。
  var unspecifiedTimesNote: String? {
    guard case .frequency = self else { return nil }
    return String(localized: "Times of day are not specified in this record.")
  }
}

extension PatientMedicationsViewModel.TimeOfDay {

  var text: String { String(format: "%02d:%02d", hour, minute) }
}

extension PatientMedicationsViewModel.PeriodUnit {

  /// 週期的文字。`count` 為 1 時用單數、否則帶上數量。
  func periodText(count: Double) -> String {
    guard count != 1 else { return singular }
    return String(localized: "\(count.formatted(.number.precision(.fractionLength(0...2)))) \(plural)")
  }

  private var singular: String {
    switch self {
    case .second: String(localized: "second")
    case .minute: String(localized: "minute")
    case .hour: String(localized: "hour")
    case .day: String(localized: "day")
    case .week: String(localized: "week")
    case .month: String(localized: "month")
    case .year: String(localized: "year")
    // 認不得的碼原樣顯示——它是記錄的一部分，換成「未知」會把資訊丟掉。
    case let .other(code): code
    }
  }

  private var plural: String {
    switch self {
    case .second: String(localized: "seconds")
    case .minute: String(localized: "minutes")
    case .hour: String(localized: "hours")
    case .day: String(localized: "days")
    case .week: String(localized: "weeks")
    case .month: String(localized: "months")
    case .year: String(localized: "years")
    case let .other(code): code
    }
  }
}
