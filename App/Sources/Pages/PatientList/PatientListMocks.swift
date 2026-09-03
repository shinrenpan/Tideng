#if DEBUG
import Foundation
import FHIRClient

extension PatientListViewModel.Patient {

  static let mock: Self = .init(
    id: "p-001",
    name: "王小明",
    gender: .male,
    birthDate: DateComponents(year: 1958, month: 3, day: 14),
    recordNumber: "A123456"
  )

  static let mocks: [Self] = [
    .init(id: "p-001", name: "王小明", gender: .male,
          birthDate: DateComponents(year: 1958, month: 3, day: 14), recordNumber: "A123456"),
    .init(id: "p-002", name: "陳美玲", gender: .female,
          birthDate: DateComponents(year: 1972, month: 11, day: 2), recordNumber: "A234567"),
    .init(id: "p-003", name: "林建宏", gender: .male,
          birthDate: DateComponents(year: 1945, month: 6), recordNumber: "A345678"),
    // 只有年份的生日：FHIR 的 date 允許這種精度，實務上舊資料常見。
    .init(id: "p-004", name: "黃淑芬", gender: .female,
          birthDate: DateComponents(year: 1989), recordNumber: nil),
    // 沒有姓名與病歷號的極簡資料，用來檢查版面不會塌。
    .init(id: "p-005", name: "未命名", gender: .unknown,
          birthDate: nil, recordNumber: nil),
    .init(id: "p-006", name: "John Smith", gender: .male,
          birthDate: DateComponents(year: 1980, month: 1, day: 20), recordNumber: "F001122")
  ]
}

extension FHIRClient {

  /// Preview 專用。指向一個不存在的位址——Preview 已注入 state 並關掉 run-once 旗標，
  /// 不會真的發出請求；這個 client 只是為了讓 ViewModel 建得起來。
  static var preview: FHIRClient {
    // swiftlint:disable:next force_try
    try! FHIRClient(baseURL: URL(string: "https://preview.invalid/fhir")!)
  }
}
#endif
