import Foundation
import Testing
import FHIRCore
import FHIRClient
@testable import Tideng

@MainActor
struct PatientEncountersViewModelTests {

  private let identity = PatientEncountersViewModel.PatientIdentity(id: "p1", name: "王志明")

  private func makeViewModel() throws -> PatientEncountersViewModel {
    PatientEncountersViewModel(client: try TestSupport.makeClient(), patient: identity)
  }

  /// 一次就診。`start` / `end` 為 nil 表示記錄沒有那一半。
  private func encounter(
    id: String, status: String = "finished",
    start: String?, end: String? = nil,
    participant: String? = nil
  ) -> String {
    let period = [start.map { #""start": "\#($0)""# }, end.map { #""end": "\#($0)""# }]
      .compactMap { $0 }
    let periodField = period.isEmpty ? "" : #", "period": { \#(period.joined(separator: ",")) }"#
    let participantField = participant.map {
      #", "participant": [{ "individual": { "reference": "\#($0)" } }]"#
    } ?? ""

    return """
    { "resource": { "resourceType": "Encounter", "id": "\(id)", "status": "\(status)",
        "class": { "system": "http://terminology.hl7.org/CodeSystem/v3-ActCode",
                   "code": "AMB", "display": "門診" },
        "subject": { "reference": "Patient/p1" }\(periodField)\(participantField) } }
    """
  }

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

  // MARK: - 排序

  @Test
  func `亂序回應依開始時間新到舊排列`() async throws {
    // 排序由 client 完成，不依賴 server 的 `_sort`——它只認少數欄位，
    // 未知欄位靜默丟棄，那會讓「有沒有排序」變成看不見的差異。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e2", start: TestSupport.iso8601(hoursAgo: 30)),
      encounter(id: "e3", start: TestSupport.iso8601(hoursAgo: 2)),
      encounter(id: "e1", start: TestSupport.iso8601(hoursAgo: 72))
    ])))))

    #expect(viewModel.state.encounters.map(\.id) == ["e3", "e2", "e1"])
  }

  @Test
  func `沒有 period 的就診排在最後`() async throws {
    // 沒有時間就沒有位置可言。硬塞進時間序等於替它編一個時間。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "none", status: "planned", start: nil),
      encounter(id: "recent", start: TestSupport.iso8601(hoursAgo: 2))
    ])))))

    #expect(viewModel.state.encounters.map(\.id) == ["recent", "none"])
  }

  // MARK: - period 的三種形態

  @Test
  func `有頭有尾的就診兩個時間都在`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", start: TestSupport.iso8601(hoursAgo: 30), end: TestSupport.iso8601(hoursAgo: 29))
    ])))))

    let encounter = try #require(viewModel.state.encounters.first)
    #expect(encounter.startedAt != nil)
    #expect(encounter.endedAt != nil)
    #expect(encounter.hasOpenPeriod == false)
    #expect(encounter.hasNoPeriod == false)
  }

  @Test
  func `只有開始時間的就診是開放式 period 且不以當下時間替代`() async throws {
    // 開放式 period 在 FHIR 裡代表「尚未結束，或結束時間未被記錄」。
    // 填上當下時間會斷言記錄沒說的事。
    let before = Date()
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", status: "in-progress", start: TestSupport.iso8601(hoursAgo: 2))
    ])))))

    let encounter = try #require(viewModel.state.encounters.first)
    #expect(encounter.hasOpenPeriod)
    #expect(encounter.endedAt == nil)
    // 畫面上不得出現任何「現在」——沒有任何欄位落在這段執行區間內。
    let after = Date()
    for child in Mirror(reflecting: encounter).children {
      if let date = child.value as? Date {
        #expect(!(date >= before && date <= after), "不得以當下時間替代缺少的 end")
      }
    }
  }

  @Test
  func `完全沒有 period 時不宣稱進行中`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", status: "planned", start: nil)
    ])))))

    let encounter = try #require(viewModel.state.encounters.first)
    #expect(encounter.hasNoPeriod)
    // 「沒有記錄時間」與「還開著」是不同的事，不能混為一談。
    #expect(encounter.hasOpenPeriod == false)
    #expect(encounter.startedAt == nil)
    #expect(encounter.endedAt == nil)
  }

  @Test
  func `status 與 period 矛盾時顯示記錄的 status`() async throws {
    // status 說結束了、period 沒有 end 是完全合法的資料。
    // 兩者是獨立的事實，調和它們就是替記錄做決定。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", status: "finished", start: TestSupport.iso8601(hoursAgo: 72))
    ])))))

    let encounter = try #require(viewModel.state.encounters.first)
    #expect(encounter.status == .finished)
    #expect(encounter.hasOpenPeriod)
  }

  @Test
  func `class 取 display 沒有就取 code`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(TestSupport.response(
      try TestSupport.bundle("""
      { "resourceType": "Bundle", "type": "searchset", "entry": [
        { "resource": { "resourceType": "Encounter", "id": "e1", "status": "finished",
            "class": { "code": "AMB" }, "subject": { "reference": "Patient/p1" } } }
      ] }
      """)
    )))))

    #expect(try #require(viewModel.state.encounters.first).classDisplay == "AMB")
  }

  // MARK: - participant

  @Test
  func `參與者解析為姓名`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", start: TestSupport.iso8601(hoursAgo: 2), participant: "Practitioner/practitioner-1"),
      practitioner(id: "practitioner-1", family: "何", given: "宗霖")
    ])))))

    let participant = try #require(viewModel.state.encounters.first?.participants.first)
    #expect(participant.name == "何宗霖")
  }

  @Test
  func `參與者解析不到時仍列出該筆就診並顯示 reference`() async throws {
    // 解析失敗不得讓整頁失敗，也不得讓那一筆消失——一個未解析的 reference
    // 仍然指得出是誰，比空白有用。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", start: TestSupport.iso8601(hoursAgo: 2), participant: "Practitioner/unknown-9")
    ])))))

    let encounter = try #require(viewModel.state.encounters.first)
    #expect(encounter.id == "e1")
    let participant = try #require(encounter.participants.first)
    #expect(participant.name == nil)
    #expect(participant.id == "Practitioner/unknown-9")
  }

  // MARK: - 四態

  @Test
  func `四種狀態各自到位`() async throws {
    let viewModel = try makeViewModel()
    #expect(viewModel.state.api.loadEncounters == .prepare)

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([])))))
    #expect(viewModel.state.api.loadEncounters == .success)
    #expect(viewModel.state.encounters.isEmpty)

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", start: TestSupport.iso8601(hoursAgo: 2))
    ])))))
    #expect(viewModel.state.api.loadEncounters == .success)
    #expect(viewModel.state.encounters.count == 1)

    await viewModel.doAction(.apiResponse(.encounters(.failure(.transport(message: "boom")))))
    if case .error = viewModel.state.api.loadEncounters {} else {
      Issue.record("失敗應該進入 error 狀態")
    }
  }

  @Test
  func `已有內容時失敗不清空`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.encounters(.success(try bundle([
      encounter(id: "e1", start: TestSupport.iso8601(hoursAgo: 2))
    ])))))
    await viewModel.doAction(.apiResponse(.encounters(.failure(.transport(message: "boom")))))

    #expect(viewModel.state.encounters.map(\.id) == ["e1"])
  }
}
