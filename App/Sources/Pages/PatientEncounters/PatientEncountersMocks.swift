#if DEBUG
import Foundation

extension PatientEncountersViewModel.Encounter {

  /// 三種 period 形態各一筆——這一頁的重點就在它們的差別。
  static let mocks: [Self] = [
    .init(
      id: "e1", status: .inProgress, classDisplay: "門診",
      startedAt: Date().addingTimeInterval(-2 * 3600), endedAt: nil,
      participants: [.init(id: "Practitioner/practitioner-1", name: "何宗霖")]
    ),
    .init(
      id: "e2", status: .finished, classDisplay: "門診",
      startedAt: Date().addingTimeInterval(-30 * 3600),
      endedAt: Date().addingTimeInterval(-29 * 3600),
      participants: [.init(id: "Practitioner/practitioner-3", name: "邱承翰")]
    ),
    // status 說結束了，period 卻沒有 end——合法且常見。畫面顯示記錄的 status，
    // 同時如實呈現 period 的形狀，不替兩者調和。
    .init(
      id: "e3", status: .finished, classDisplay: "門診",
      startedAt: Date().addingTimeInterval(-72 * 3600), endedAt: nil,
      participants: [.init(id: "Practitioner/practitioner-9", name: nil)]
    ),
    // 完全沒有 period：不能說何時開始，也不能宣稱它還開著。
    .init(
      id: "e4", status: .planned, classDisplay: "門診",
      startedAt: nil, endedAt: nil, participants: []
    )
  ]
}
#endif
