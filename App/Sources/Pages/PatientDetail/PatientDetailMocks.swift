#if DEBUG
import Foundation

extension PatientDetailViewModel.PatientIdentity {

  static let mock: Self = .init(
    id: "p-001", name: "王志明", gender: "男", age: 68, recordNumber: "A0000001"
  )

  /// 缺生日與病歷號——用來確認那兩行整段消失而不是留白。
  static let sparse: Self = .init(
    id: "p-005", name: "Unnamed", gender: nil, age: nil, recordNumber: nil
  )
}

extension PatientDetailViewModel.VitalSeries {

  /// 帶參考範圍，且最後一點落在範圍外。
  static var temperature: Self {
    .init(
      code: "8310-5",
      serverDisplay: "體溫",
      serverUnit: "°C",
      unitCode: "Cel",
      referenceRange: .init(low: 36.0, high: 37.5),
      points: points(values: [36.8, 37.1, 37.4, 38.8])
    )
  }

  /// server 沒給參考範圍——圖上不該出現任何帶子。
  static var oxygenSaturation: Self {
    .init(
      code: "59408-5",
      serverDisplay: "血氧飽和度",
      serverUnit: "%",
      unitCode: "%",
      referenceRange: nil,
      points: points(values: [97, 96, 95, 91])
    )
  }

  /// 只有一個點，確認不會畫出空圖。
  static var singlePoint: Self {
    .init(
      code: "8867-4",
      serverDisplay: "心跳速率",
      serverUnit: "次/分",
      unitCode: "/min",
      referenceRange: .init(low: 60, high: 100),
      points: points(values: [78])
    )
  }

  private static func points(values: [Double]) -> [PatientDetailViewModel.DataPoint] {
    values.enumerated().map { index, value in
      .init(
        id: "p\(index)",
        recordedAt: Date().addingTimeInterval(Double(index - values.count) * 6 * 3600),
        value: value
      )
    }
  }
}
#endif
