import Foundation
import FHIRCore

// MARK: - State

extension PatientDetailViewModel {

  struct State: Equatable, Sendable {
    var isFirstAppear: Bool = true
    /// 由清單傳入，不重查——清單已經有這些資料，重查只會讓畫面先空白再填上。
    var patient: PatientIdentity
    var series: [VitalSeries] = []
    var api: API = .init()
  }

  struct API: Equatable, Sendable {
    var loadVitals: Status = .prepare
  }

  enum Status: Equatable, Sendable {
    case prepare
    case loading
    case success
    case error(message: String)
  }
}

// MARK: - Domain Models

extension PatientDetailViewModel {

  /// 病人的身分資料。全部是 primitive，跨 feature 邊界時原樣傳遞。
  struct PatientIdentity: Equatable, Sendable {
    let id: String
    let name: String
    let gender: String?
    let age: Int?
    let recordNumber: String?
  }

  /// 一種生命徵象的時序。
  struct VitalSeries: Identifiable, Equatable, Sendable {
    /// LOINC code，同時作為識別。
    let code: String
    /// server 提供的名稱。已知的 code 由 V 層改用在地化名稱，未知的就顯示這個。
    let serverDisplay: String
    let unit: String
    /// server 提供的參考範圍。`nil` 表示 server 沒給——**不得以內建值頂替**。
    let referenceRange: ReferenceBounds?
    /// 依時間遞增排序。排序在轉換階段完成，View 不負責排序。
    let points: [DataPoint]

    var id: String { code }
  }

  struct DataPoint: Identifiable, Equatable, Sendable {
    let id: String
    let recordedAt: Date
    let value: Double
  }

  /// server 提供的上下界。至少有一邊。
  struct ReferenceBounds: Equatable, Sendable {
    let low: Double?
    let high: Double?
  }
}

// MARK: - DTOs

extension MainViewModel {}

extension PatientDetailViewModel.VitalSeries {

  /// 把一批觀測值整理成可繪製的時序。
  ///
  /// 三件事在這裡完成，View 拿到的就是可以直接畫的資料：
  /// 濾除畫不出來的點、依種類分組、依時間排序。
  static func series(from observations: [FHIR.Observation]) -> [Self] {
    let plottable = observations.compactMap(PlottableObservation.init)

    let grouped = Dictionary(grouping: plottable, by: \.code)

    return grouped
      .compactMap { code, group -> Self? in
        guard let first = group.first else { return nil }
        return .init(
          code: code,
          serverDisplay: first.display,
          unit: first.unit,
          referenceRange: first.bounds,
          // server 的排序不可信（`_sort` 的未知欄位是靜默丟棄的），一律自己排
          points: group
            .sorted { $0.recordedAt < $1.recordedAt }
            .map { .init(id: $0.id, recordedAt: $0.recordedAt, value: $0.value) }
        )
      }
      // 種類之間的順序固定，否則每次載入圖表會跳動
      .sorted { $0.code < $1.code }
  }
}

/// 中間表示：只有同時具備數值與時間的觀測值才畫得出來。
private struct PlottableObservation {

  let id: String
  let code: String
  let display: String
  let unit: String
  let recordedAt: Date
  let value: Double
  let bounds: PatientDetailViewModel.ReferenceBounds?

  init?(_ observation: FHIR.Observation) {
    // 一個資料點需要兩個座標，缺任一個都畫不出來
    guard let recordedAt = observation.recordedAt,
          case let .quantity(quantity) = observation.value,
          let measured = quantity.value?.value?.decimal,
          let coding = observation.code.coding?.first,
          let code = coding.code?.value?.string
    else { return nil }

    self.id = observation.id?.value?.string ?? UUID().uuidString
    self.code = code
    self.display = coding.display?.value?.string
      ?? observation.code.text?.value?.string
      ?? code
    self.unit = quantity.unit?.value?.string ?? ""
    self.recordedAt = recordedAt
    self.value = NSDecimalNumber(decimal: measured).doubleValue

    // 只採用 server 提供的範圍。沒有就是沒有，不套用任何內建值。
    let range = observation.referenceRange?.first {
      $0.low?.value?.value != nil || $0.high?.value?.value != nil
    }
    self.bounds = range.map { range in
      .init(
        low: (range.low?.value?.value?.decimal).map { NSDecimalNumber(decimal: $0).doubleValue },
        high: (range.high?.value?.value?.decimal).map { NSDecimalNumber(decimal: $0).doubleValue }
      )
    }
  }
}
