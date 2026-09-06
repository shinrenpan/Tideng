import Foundation
import Testing
import FHIRCore
import FHIRClient
@testable import Tideng

@MainActor
struct PatientMedicationsViewModelTests {

  private let identity = PatientMedicationsViewModel.PatientIdentity(id: "p1", name: "王志明")

  private func makeViewModel() throws -> PatientMedicationsViewModel {
    PatientMedicationsViewModel(client: try TestSupport.makeClient(), patient: identity)
  }

  /// 一張處方。`dosages` 是原始的 `dosageInstruction` JSON 片段。
  private func prescription(
    id: String, medication: String = "Amoxicillin 500mg 膠囊",
    status: String = "active", authoredHoursAgo: Double? = 24,
    requester: String? = "Practitioner/practitioner-1",
    dosages: [String] = []
  ) -> String {
    let authored = authoredHoursAgo.map {
      #", "authoredOn": "\#(TestSupport.iso8601(hoursAgo: $0))""#
    } ?? ""
    let requesterField = requester.map { #", "requester": { "reference": "\#($0)" }"# } ?? ""
    let dosageField = dosages.isEmpty
      ? ""
      : #", "dosageInstruction": [\#(dosages.joined(separator: ","))]"#

    return """
    { "resource": { "resourceType": "MedicationRequest", "id": "\(id)",
        "intent": "order", "status": "\(status)",
        "medicationCodeableConcept": { "text": "\(medication)" },
        "subject": { "reference": "Patient/p1" }\(authored)\(requesterField)\(dosageField) } }
    """
  }

  /// 一天 N 次，**沒有** `timeOfDay`——最常見，也是最容易被實作自行填上時間的一種。
  private func unspecifiedTimes(count: Int, dose: Double = 1) -> String {
    """
    { "timing": { "repeat": { "frequency": \(count), "period": 1, "periodUnit": "d" } },
      "doseAndRate": [{ "doseQuantity": { "value": \(dose), "unit": "錠",
        "system": "http://unitsofmeasure.org", "code": "{tablet}" } }] }
    """
  }

  private func explicitTimes(_ times: [String]) -> String {
    """
    { "timing": { "repeat": { "frequency": \(times.count), "period": 1, "periodUnit": "d",
        "timeOfDay": [\(times.map { "\"\($0)\"" }.joined(separator: ","))] } },
      "doseAndRate": [{ "doseQuantity": { "value": 1, "unit": "錠",
        "system": "http://unitsofmeasure.org", "code": "{tablet}" } }] }
    """
  }

  private let asNeeded = """
  { "asNeededCodeableConcept": { "text": "發燒或疼痛" },
    "doseAndRate": [{ "doseQuantity": { "value": 1, "unit": "錠",
      "system": "http://unitsofmeasure.org", "code": "{tablet}" } }] }
  """

  private func practitioner(id: String, family: String, given: String) -> String {
    """
    { "resource": { "resourceType": "Practitioner", "id": "\(id)",
        "name": [{ "family": "\(family)", "given": ["\(given)"] }] } }
    """
  }

  private func bundle(_ entries: [String]) throws -> FHIRBundleDecoder.Result {
    TestSupport.response(try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "entry": [\(entries.joined(separator: ","))] }
    """))
  }

  /// 一筆處方在畫面上會出現的所有文字。
  ///
  /// 「不得出現具體時間」是這一頁唯一真正要守住的性質，所以斷言必須落在
  /// **畫面文字**上，而不是落在中間的資料結構——資料結構正確但文字多說一句，
  /// 使用者看到的仍然是錯的。
  private func visibleText(_ prescription: PatientMedicationsViewModel.Prescription) -> [String] {
    var text: [String] = []
    if let medication = prescription.medication { text.append(medication) }
    if let requester = prescription.requester { text.append(requester.name ?? requester.reference) }
    for dosage in prescription.dosages {
      if let schedule = dosage.schedule {
        text.append(schedule.text)
        if let note = schedule.unspecifiedTimesNote { text.append(note) }
      }
    }
    return text
  }

  // MARK: - 基本欄位

  @Test
  func `每筆處方顯示藥品 status 與 requester`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", dosages: [unspecifiedTimes(count: 3)]),
      prescription(id: "mr2", medication: "Metformin 500mg 錠", authoredHoursAgo: 48,
                   dosages: [explicitTimes(["08:00:00", "18:00:00"])]),
      practitioner(id: "practitioner-1", family: "何", given: "宗霖")
    ])))))

    #expect(viewModel.state.prescriptions.count == 2)
    for prescription in viewModel.state.prescriptions {
      #expect(prescription.medication != nil)
      #expect(prescription.status == .active)
      #expect(prescription.requester?.name == "何宗霖")
    }
  }

  @Test
  func `開立者解析不到時顯示 reference`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", requester: "Practitioner/unknown-9")
    ])))))

    let requester = try #require(viewModel.state.prescriptions.first?.requester)
    #expect(requester.name == nil)
    #expect(requester.reference == "Practitioner/unknown-9")
  }

  @Test
  func `亂序回應依開立時間新到舊排列`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr2", authoredHoursAgo: 48),
      prescription(id: "mr3", authoredHoursAgo: 2),
      prescription(id: "mr1", authoredHoursAgo: 120)
    ])))))

    #expect(viewModel.state.prescriptions.map(\.id) == ["mr3", "mr2", "mr1"])
  }

  // MARK: - 時程照實呈現

  @Test
  func `一天三次而未指定時間時畫面不出現任何具體時間`() async throws {
    // 本案最主要的一條臨床紅線。「一天三次」是一句完整而合法的醫囑，它**沒有**說
    // 是哪三次——那三個時間點由機構的給藥常規決定，不在 FHIR 資料裡。
    // 填上 08:00／16:00／24:00 等於把假設當成處方呈現。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", dosages: [unspecifiedTimes(count: 3)])
    ])))))

    let prescription = try #require(viewModel.state.prescriptions.first)
    let schedule = try #require(prescription.dosages.first?.schedule)

    // 記錄說了次數與週期，就說次數與週期。
    #expect(schedule == .frequency(count: 3, period: 1, unit: .day))
    #expect(schedule.statesClockTimes == false)
    // 而且必須**明說**它沒有指定時間——留白會被讀成「沒有時程」。
    #expect(schedule.unspecifiedTimesNote != nil)

    // 畫面上的每一段文字都不得含時鐘格式。
    let clock = try Regex(#"\d{1,2}:\d{2}"#)
    for text in visibleText(prescription) {
      #expect(text.firstMatch(of: clock) == nil, "「\(text)」出現了記錄沒有指定的時間")
    }
  }

  @Test
  func `記錄有指定時間時就顯示那些時間`() async throws {
    // 對照組：這些時間在記錄裡，照著顯示才是忠實。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", dosages: [explicitTimes(["08:00:00", "18:00:00"])])
    ])))))

    let schedule = try #require(viewModel.state.prescriptions.first?.dosages.first?.schedule)
    #expect(schedule == .atTimes([.init(hour: 8, minute: 0), .init(hour: 18, minute: 0)]))
    #expect(schedule.statesClockTimes)
    #expect(schedule.text == "08:00, 18:00")
    // 有指定時間的那一筆不需要「未指定」的說明。
    #expect(schedule.unspecifiedTimesNote == nil)
  }

  @Test
  func `需要時服用不呈現任何時程`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", dosages: [asNeeded])
    ])))))

    let prescription = try #require(viewModel.state.prescriptions.first)
    let schedule = try #require(prescription.dosages.first?.schedule)
    #expect(schedule == .asNeeded(reason: "發燒或疼痛"))
    #expect(schedule.statesClockTimes == false)
    // 「需要時」不是「時程未知」，所以不加未指定的說明。
    #expect(schedule.unspecifiedTimesNote == nil)

    let clock = try Regex(#"\d{1,2}:\d{2}"#)
    for text in visibleText(prescription) {
      #expect(text.firstMatch(of: clock) == nil)
    }
  }

  @Test
  func `讀不懂的 timing 顯示為未指定而不是留白`() async throws {
    // 「有時程但我們看不懂」與「沒有時程」是不同的事。留白會把前者說成後者。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", dosages: [#"{ "timing": { "code": { "text": "TID" } } }"#])
    ])))))

    let schedule = try #require(viewModel.state.prescriptions.first?.dosages.first?.schedule)
    #expect(schedule == .unreadable)
    #expect(schedule.text.isEmpty == false)
  }

  // MARK: - 多段 dosageInstruction

  @Test
  func `多段遞減劑量全部顯示且順序與記錄一致`() async throws {
    // 多段是「劑量隨時間改變」的表達方式，合併成一段就把它存在的理由抹掉了。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", medication: "Prednisolone 5mg 錠", dosages: [
        unspecifiedTimes(count: 1, dose: 4),
        unspecifiedTimes(count: 1, dose: 2),
        unspecifiedTimes(count: 1, dose: 1)
      ])
    ])))))

    let prescription = try #require(viewModel.state.prescriptions.first)
    #expect(prescription.dosages.count == 3)
    #expect(prescription.dosages.compactMap { $0.dose?.value } == [4, 2, 1])
  }

  @Test
  func `沒有 dosageInstruction 時只顯示藥品`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1", medication: "Salbutamol 吸入劑", dosages: [])
    ])))))

    let prescription = try #require(viewModel.state.prescriptions.first)
    #expect(prescription.medication == "Salbutamol 吸入劑")
    // 沒有劑量行，也不填補任何東西。
    #expect(prescription.dosages.isEmpty)
  }

  // MARK: - 四態

  @Test
  func `四種狀態各自到位`() async throws {
    let viewModel = try makeViewModel()
    #expect(viewModel.state.api.loadPrescriptions == .prepare)

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([])))))
    #expect(viewModel.state.api.loadPrescriptions == .success)
    #expect(viewModel.state.prescriptions.isEmpty)

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1")
    ])))))
    #expect(viewModel.state.api.loadPrescriptions == .success)
    #expect(viewModel.state.prescriptions.count == 1)

    await viewModel.doAction(.apiResponse(.prescriptions(.failure(.transport(message: "boom")))))
    if case .error = viewModel.state.api.loadPrescriptions {} else {
      Issue.record("失敗應該進入 error 狀態")
    }
  }

  @Test
  func `已有內容時失敗不清空`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.prescriptions(.success(try bundle([
      prescription(id: "mr1")
    ])))))
    await viewModel.doAction(.apiResponse(.prescriptions(.failure(.transport(message: "boom")))))

    #expect(viewModel.state.prescriptions.map(\.id) == ["mr1"])
  }
}
