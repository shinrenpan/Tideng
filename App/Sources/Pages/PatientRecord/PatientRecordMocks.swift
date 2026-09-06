#if DEBUG
import Foundation

extension PatientRecordViewModel.Record {

  static let mock: Self = .init(
    name: "王志明",
    gender: .male,
    birthDate: DateComponents(year: 1958, month: 3, day: 12),
    recordNumber: "A0000001",
    nationalIdentifier: "A100000001"
  )

  /// 記錄不完整的一筆。這是 demo 的重點之一：缺的欄位整行不見，而不是留一排「—」。
  static let sparseMock: Self = .init(
    name: "陳美玲",
    gender: nil,
    birthDate: nil,
    recordNumber: nil,
    nationalIdentifier: nil
  )
}
#endif
