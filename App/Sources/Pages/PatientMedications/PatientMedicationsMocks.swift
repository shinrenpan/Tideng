#if DEBUG
import Foundation

extension PatientMedicationsViewModel.Prescription {

  /// 四種時程形態各一筆，與 seed 的四種對齊——這一頁的重點就在它們的差別。
  static let mocks: [Self] = [
    // 一天三次，記錄沒有指定是哪三次。
    .init(
      id: "mr1", medication: "Amoxicillin 500mg 膠囊", status: .active,
      requester: .init(reference: "Practitioner/practitioner-1", name: "何宗霖"),
      authoredOn: Date().addingTimeInterval(-24 * 3600),
      dosages: [
        .init(id: "mr1-0", dose: .init(value: 1, unit: "膠囊"),
              schedule: .frequency(count: 3, period: 1, unit: .day))
      ]
    ),
    // 記錄有指定時間——對照組。
    .init(
      id: "mr2", medication: "Metformin 500mg 錠", status: .active,
      requester: .init(reference: "Practitioner/practitioner-3", name: "邱承翰"),
      authoredOn: Date().addingTimeInterval(-48 * 3600),
      dosages: [
        .init(id: "mr2-0", dose: .init(value: 1, unit: "錠"),
              schedule: .atTimes([.init(hour: 8, minute: 0), .init(hour: 18, minute: 0)]))
      ]
    ),
    // 多段遞減：合併成一段就把它存在的理由抹掉了。
    .init(
      id: "mr3", medication: "Prednisolone 5mg 錠", status: .active,
      requester: .init(reference: "Practitioner/practitioner-1", name: "何宗霖"),
      authoredOn: Date().addingTimeInterval(-72 * 3600),
      dosages: [
        .init(id: "mr3-0", dose: .init(value: 4, unit: "錠"),
              schedule: .frequency(count: 1, period: 1, unit: .day)),
        .init(id: "mr3-1", dose: .init(value: 2, unit: "錠"),
              schedule: .frequency(count: 1, period: 1, unit: .day)),
        .init(id: "mr3-2", dose: .init(value: 1, unit: "錠"),
              schedule: .frequency(count: 1, period: 1, unit: .day))
      ]
    ),
    // 需要時服用：沒有時程可言。
    .init(
      id: "mr4", medication: "Acetaminophen 500mg 錠", status: .active,
      requester: .init(reference: "Practitioner/practitioner-3", name: "邱承翰"),
      authoredOn: Date().addingTimeInterval(-96 * 3600),
      dosages: [
        .init(id: "mr4-0", dose: .init(value: 1, unit: "錠"),
              schedule: .asNeeded(reason: "發燒或疼痛"))
      ]
    ),
    // 記錄沒有給藥指示：只顯示藥品，不填補。
    .init(
      id: "mr5", medication: "Salbutamol 吸入劑", status: .completed,
      requester: .init(reference: "Practitioner/practitioner-9", name: nil),
      authoredOn: Date().addingTimeInterval(-120 * 3600),
      dosages: []
    )
  ]
}
#endif
