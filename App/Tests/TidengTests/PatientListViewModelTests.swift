import Foundation
import Testing
import FHIRCore
import FHIRClient
import UIKit
@testable import Tideng

/// MVVMC 的測試哲學：直接以 `doAction(.apiResponse(...))` 注入結果，
/// 不需要 protocol、不需要 mock class、不需要攔截網路。
@MainActor
struct PatientListViewModelTests {

  private func makeViewModel(slice: PatientListViewModel.Slice = .all) throws -> PatientListViewModel {
    PatientListViewModel(client: try TestSupport.makeClient(), sliceIdentifier: slice.rawValue)
  }

  private func bundle(_ resources: String...) throws -> FHIR.Bundle {
    let entries = resources.map { "{ \"resource\": \($0) }" }.joined(separator: ",")
    return try TestSupport.bundle("{ \"resourceType\": \"Bundle\", \"type\": \"searchset\", \"entry\": [\(entries)] }")
  }

  // MARK: - 初始狀態與基本轉換

  @Test
  func `初始狀態未載入任何資料`() throws {
    let viewModel = try makeViewModel()

    #expect(viewModel.state.isFirstAppear)
    #expect(viewModel.state.patients.isEmpty)
    #expect(viewModel.state.api.loadPatients == .prepare)
  }

  @Test
  func `注入成功回應後 DTO 轉成 Domain Model 寫進 state`() async throws {
    let viewModel = try makeViewModel()
    let response = try bundle(#"{"resourceType":"Patient","id":"p1","name":[{"family":"王","given":["小明"]}],"gender":"male"}"#)

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(response)))))

    #expect(viewModel.state.patients.count == 1)
    #expect(viewModel.state.patients.first?.name == "王小明")
    #expect(viewModel.state.patients.first?.gender == .male)
    #expect(viewModel.state.api.loadPatients == .success)
  }

  @Test
  func `沒有 id 的資源被濾掉因為 UI 無法定位它`() async throws {
    let viewModel = try makeViewModel()
    let response = try bundle(
      #"{"resourceType":"Patient","id":"p1"}"#,
      #"{"resourceType":"Patient"}"#
    )

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(response)))))

    #expect(viewModel.state.patients.count == 1)
    #expect(viewModel.state.patients.first?.id == "p1")
  }

  @Test
  func `刷新失敗不清空已在畫面上的資料`() async throws {
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(try bundle(#"{"resourceType":"Patient","id":"p1"}"#))))))

    await viewModel.doAction(.apiResponse(.patients(.failure(.transport(message: "offline")))))

    #expect(viewModel.state.patients.count == 1)
    guard case .error = viewModel.state.api.loadPatients else {
      Issue.record("預期進入 error 狀態")
      return
    }
  }

  // MARK: - 關鍵字過濾

  @Test
  func `關鍵字命中姓名`() async throws {
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(try bundle(
      #"{"resourceType":"Patient","id":"p1","name":[{"family":"王","given":["小明"]}]}"#,
      #"{"resourceType":"Patient","id":"p2","name":[{"family":"陳","given":["美玲"]}]}"#
    ))))))

    viewModel.state.keyword = "美玲"

    #expect(viewModel.state.filteredPatients.count == 1)
    #expect(viewModel.state.filteredPatients.first?.name == "陳美玲")
  }

  @Test
  func `關鍵字命中病歷號時該病人仍留在清單`() async throws {
    // 關鍵字沒有出現在姓名裡，只出現在病歷號——護理師常以病歷號找人。
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(try bundle(
      #"{"resourceType":"Patient","id":"p1","name":[{"family":"王","given":["小明"]}],"identifier":[{"type":{"coding":[{"code":"MR"}]},"value":"A123456"}]}"#,
      #"{"resourceType":"Patient","id":"p2","name":[{"family":"陳","given":["美玲"]}],"identifier":[{"type":{"coding":[{"code":"MR"}]},"value":"B999999"}]}"#
    ))))))

    viewModel.state.keyword = "A123456"

    #expect(viewModel.state.filteredPatients.count == 1)
    #expect(viewModel.state.filteredPatients.first?.recordNumber == "A123456")
  }

  @Test
  func `關鍵字無結果時已取得的病人不被清空`() async throws {
    // filteredPatients 為空、patients 仍在——View 才分得出「搜尋無結果」與「伺服器沒資料」。
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(try bundle(
      #"{"resourceType":"Patient","id":"p1","name":[{"family":"王","given":["小明"]}]}"#
    ))))))

    viewModel.state.keyword = "zzz-no-match"

    #expect(viewModel.state.filteredPatients.isEmpty)
    #expect(viewModel.state.patients.count == 1)
  }

  @Test
  func `關鍵字為空時顯示全部`() async throws {
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(try bundle(
      #"{"resourceType":"Patient","id":"p1"}"#,
      #"{"resourceType":"Patient","id":"p2"}"#
    ))))))

    viewModel.state.keyword = ""

    #expect(viewModel.state.filteredPatients.count == 2)
  }

  // MARK: - 切片決定查詢條件

  @Test
  func `每個切片各自對應不同的查詢`() throws {
    let searches = PatientListViewModel.Slice.allCases.map { ($0, $0.search) }

    let byResourceType = Dictionary(uniqueKeysWithValues: searches.map { ($0.0, $0.1.resourceType) })
    #expect(byResourceType[.all] == "Patient")
    #expect(byResourceType[.seenToday] == "Encounter")
    #expect(byResourceType[.outOfRange] == "Observation")
    #expect(byResourceType[.onMedication] == "MedicationRequest")
  }

  @Test
  func `切片以字串識別碼建構不需要認識主畫面的型別`() throws {
    for slice in PatientListViewModel.Slice.allCases {
      let viewModel = try makeViewModel(slice: slice)
      #expect(viewModel.state.slice == slice)
    }
  }

  @Test
  func `識別碼對不上時退回全部病人而不是空清單`() throws {
    // 識別碼來自 app 內部，理論上不會錯；真的錯了，顯示全部比顯示空白有用。
    let viewModel = PatientListViewModel(
      client: try TestSupport.makeClient(),
      sliceIdentifier: "not-a-real-slice"
    )
    #expect(viewModel.state.slice == .all)
  }

  @Test
  func `HostController 只收 client 與字串切片`() throws {
    // 建得起來就代表跨界簽名裡沒有任何 Domain Model——若曾經傳過
    // PatientListViewModel.Slice，這行會編不過。
    let controller = PatientListHostController(
      client: try TestSupport.makeClient(),
      sliceIdentifier: PatientListViewModel.Slice.seenToday.rawValue
    )
    #expect(controller.rootView.viewModel.state.slice == .seenToday)
  }

  // MARK: - 各切片從回應取出病人的方式不同

  @Test
  func `今日就診的病人來自 include 夾帶的 Patient`() async throws {
    let viewModel = try makeViewModel(slice: .seenToday)
    let response = try bundle(
      #"{"resourceType":"Encounter","id":"e1","status":"finished","class":{"code":"AMB"},"subject":{"reference":"Patient/p1"},"period":{"start":"\#(TestSupport.iso8601(daysAgo: 0))"}}"#,
      #"{"resourceType":"Patient","id":"p1","name":[{"family":"林","given":["建宏"]}]}"#
    )

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(response)))))

    #expect(viewModel.state.patients.count == 1)
    #expect(viewModel.state.patients.first?.name == "林建宏")
  }

  @Test
  func `不是今天的就診不列入今日就診`() async throws {
    // server 端的 Encounter?date= 答不出「今天來的病人」：開放式 period 會被任何
    // ge 查詢命中，所以昨天還沒結束的就診會跟著回來——client 必須自己濾掉，
    // 否則卡片說「今日」卻列出別天的人。
    let viewModel = try makeViewModel(slice: .seenToday)
    let response = try bundle(
      #"{"resourceType":"Encounter","id":"e1","status":"finished","class":{"code":"AMB"},"subject":{"reference":"Patient/p1"},"period":{"start":"\#(TestSupport.iso8601(daysAgo: 1))"}}"#,
      #"{"resourceType":"Patient","id":"p1","name":[{"family":"林","given":["建宏"]}]}"#
    )

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(response)))))

    #expect(viewModel.state.patients.isEmpty)
  }

  @Test
  func `沒有時間的就診不列入今日就診`() async throws {
    // 時間不明時寧可少算，也不要把不知道時間的資料算進一個宣稱了「今日」的清單。
    let viewModel = try makeViewModel(slice: .seenToday)
    let response = try bundle(
      #"{"resourceType":"Encounter","id":"e1","status":"in-progress","class":{"code":"AMB"},"subject":{"reference":"Patient/p1"}}"#,
      #"{"resourceType":"Patient","id":"p1","name":[{"family":"林","given":["建宏"]}]}"#
    )

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(response)))))

    #expect(viewModel.state.patients.isEmpty)
  }

  @Test
  func `超出參考值只收落在範圍外那些觀測值的病人`() async throws {
    let viewModel = try makeViewModel(slice: .outOfRange)
    let response = try bundle(
      #"{"resourceType":"Observation","id":"o1","status":"final","code":{"coding":[{"code":"8310-5"}]},"subject":{"reference":"Patient/p1"},"effectiveDateTime":"\#(TestSupport.iso8601(hoursAgo: 2))","valueQuantity":{"value":38.9},"referenceRange":[{"low":{"value":36.0},"high":{"value":37.5}}]}"#,
      #"{"resourceType":"Observation","id":"o2","status":"final","code":{"coding":[{"code":"8310-5"}]},"subject":{"reference":"Patient/p2"},"effectiveDateTime":"\#(TestSupport.iso8601(hoursAgo: 2))","valueQuantity":{"value":37.0},"referenceRange":[{"low":{"value":36.0},"high":{"value":37.5}}]}"#,
      #"{"resourceType":"Patient","id":"p1","name":[{"family":"王","given":["小明"]}]}"#,
      #"{"resourceType":"Patient","id":"p2","name":[{"family":"陳","given":["美玲"]}]}"#
    )

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(response)))))

    // p2 的體溫在範圍內，雖然它的 Patient 也被 include 夾帶回來，仍不該出現在清單裡
    #expect(viewModel.state.patients.count == 1)
    #expect(viewModel.state.patients.first?.name == "王小明")
  }

  @Test
  func `沒有參考範圍的觀測值不會讓病人進入超出參考值清單`() async throws {
    let viewModel = try makeViewModel(slice: .outOfRange)
    let response = try bundle(
      #"{"resourceType":"Observation","id":"o1","status":"final","code":{"coding":[{"code":"8310-5"}]},"subject":{"reference":"Patient/p1"},"effectiveDateTime":"\#(TestSupport.iso8601(hoursAgo: 2))","valueQuantity":{"value":41.0}}"#,
      #"{"resourceType":"Patient","id":"p1"}"#
    )

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(response)))))

    // 41.0 看起來很高，但 server 沒給範圍——判斷它異常就是臨床判讀
    #expect(viewModel.state.patients.isEmpty)
    #expect(viewModel.state.api.loadPatients == .success)
  }
}

// MARK: - 四態與病人列欄位

@MainActor
struct PatientListPresentationTests {

  private func makeViewModel() throws -> PatientListViewModel {
    PatientListViewModel(client: try TestSupport.makeClient())
  }

  private func bundle(_ resources: String...) throws -> FHIR.Bundle {
    let entries = resources.map { "{ \"resource\": \($0) }" }.joined(separator: ",")
    return try TestSupport.bundle("{ \"resourceType\": \"Bundle\", \"type\": \"searchset\", \"entry\": [\(entries)] }")
  }

  private func patient(_ json: String) throws -> PatientListViewModel.Patient {
    let viewModel = try makeViewModel()
    let response = try bundle(json)
    return try #require(
      viewModel.state.slice.patients(from: response).compactMap(PatientListViewModel.Patient.init(resource:)).first
    )
  }

  // MARK: 四態

  @Test
  func `尚未載入時清單為空且狀態為 prepare`() throws {
    let viewModel = try makeViewModel()
    #expect(viewModel.state.patients.isEmpty)
    #expect(viewModel.state.api.loadPatients == .prepare)
  }

  @Test
  func `載入成功但伺服器沒有資料時清單為空且狀態為 success`() async throws {
    // 這一態必須與「還在載入」分得開，否則 View 會一直轉圈。
    let viewModel = try makeViewModel()
    let empty = try TestSupport.bundle(#"{ "resourceType": "Bundle", "type": "searchset" }"#)

    await viewModel.doAction(.apiResponse(.patients(.success(TestSupport.response(empty)))))

    #expect(viewModel.state.patients.isEmpty)
    #expect(viewModel.state.api.loadPatients == .success)
  }

  @Test
  func `首次載入失敗時清單為空且帶著錯誤訊息`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.patients(.failure(.transport(message: "offline")))))

    #expect(viewModel.state.patients.isEmpty)
    guard case let .error(message) = viewModel.state.api.loadPatients else {
      Issue.record("預期進入 error 狀態")
      return
    }
    #expect(!message.isEmpty)
  }

  // MARK: 病人列欄位

  @Test
  func `年齡依 spec 的表格推導`() throws {
    // spec 的範例表格，基準日固定為 2026-09-03
    let today = Date(timeIntervalSince1970: 1_788_436_800)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!

    let cases: [(json: String, expected: Int?)] = [
      (#"{"resourceType":"Patient","id":"p1","birthDate":"1958-03-14"}"#, 68),
      (#"{"resourceType":"Patient","id":"p2","birthDate":"1958-11-14"}"#, 67),
      (#"{"resourceType":"Patient","id":"p3","birthDate":"1989"}"#, 37),
      (#"{"resourceType":"Patient","id":"p4"}"#, nil)
    ]

    for row in cases {
      let subject = try patient(row.json)
      #expect(subject.age(asOf: today, calendar: calendar) == row.expected)
    }
  }

  @Test
  func `只有年月的生日也能推導年齡`() throws {
    let today = Date(timeIntervalSince1970: 1_788_436_800)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!

    // 1945-06：六月已過，滿 81
    let subject = try patient(#"{"resourceType":"Patient","id":"p1","birthDate":"1945-06"}"#)
    #expect(subject.age(asOf: today, calendar: calendar) == 81)
  }

  @Test
  func `沒有姓名時顯示佔位字串而非空白`() throws {
    let subject = try patient(#"{"resourceType":"Patient","id":"p1"}"#)
    #expect(!subject.name.isEmpty)
  }

  @Test
  func `沒有 identifier 時病歷號為 nil 讓 View 整段省略`() throws {
    let subject = try patient(#"{"resourceType":"Patient","id":"p1"}"#)
    #expect(subject.recordNumber == nil)
  }

  @Test
  func `取標記為 MR 的 identifier 而非第一個`() throws {
    // 第一個往往是內部識別碼。把它當病歷號顯示，臨床人員會拿一個查不到的號碼去找人。
    let subject = try patient(#"{"resourceType":"Patient","id":"p1","identifier":[{"system":"urn:internal","value":"patient-8"},{"type":{"coding":[{"code":"MR"}]},"value":"A123456"}]}"#)
    #expect(subject.recordNumber == "A123456")
  }

  @Test
  func `沒有 MR 標記時不顯示病歷號`() throws {
    // SMART sandbox 的病人只有 UUID——顯示它並標上「病歷號」是誤導。
    let subject = try patient(#"{"resourceType":"Patient","id":"p1","identifier":[{"value":"73a7d6b7-0310-4fff-9b0b-7891a5e390f5"}]}"#)
    #expect(subject.recordNumber == nil)
  }

  @Test
  func `性別對齊 FHIR 的 value set`() throws {
    #expect(try patient(#"{"resourceType":"Patient","id":"p1","gender":"male"}"#).gender == .male)
    #expect(try patient(#"{"resourceType":"Patient","id":"p2","gender":"female"}"#).gender == .female)
    #expect(try patient(#"{"resourceType":"Patient","id":"p3","gender":"other"}"#).gender == .other)
    #expect(try patient(#"{"resourceType":"Patient","id":"p4"}"#).gender == .unknown)
  }
}

// MARK: - 終點頁分流

@MainActor
struct PatientListDestinationTests {

  private let patient = PatientListViewModel.Patient(
    id: "p1", name: "王志明", gender: .male,
    birthDate: DateComponents(year: 1958, month: 3, day: 12), recordNumber: "A0000001"
  )

  private func makeViewModel(slice: String) throws -> PatientListViewModel {
    PatientListViewModel(client: try TestSupport.makeClient(), sliceIdentifier: slice)
  }

  @Test
  func `四個切片各自導向不同的終點頁`() throws {
    // 這是本案的核心決策：終點由抵達的切片決定，不是由病人決定。
    // 四個切片若有任兩個落在同一頁，「四張卡片各自走到不同終點」就沒有成立。
    let expected: [PatientListViewModel.Slice: PatientListViewModel.Destination] = [
      .all: .record,
      .seenToday: .encounters,
      .onMedication: .medications,
      .outOfRange: .vitals
    ]

    for (slice, destination) in expected {
      let viewModel = try makeViewModel(slice: slice.rawValue)
      #expect(viewModel.state.slice.destination == destination, "\(slice.rawValue) 走錯終點")
    }

    // 每個切片都被涵蓋，而且沒有兩個落在同一頁——否則「四張卡片各自走到不同終點」
    // 只是看起來成立。
    #expect(Set(expected.keys) == Set(PatientListViewModel.Slice.allCases))
    #expect(Set(expected.values).count == PatientListViewModel.Slice.allCases.count)
  }

  @Test
  func `未知的切片識別碼導向病歷頁`() throws {
    // Patient 是四者中對任何病人都成立的那一個。不是崩潰，也不是空白畫面。
    let viewModel = try makeViewModel(slice: "no-such-slice")

    #expect(viewModel.state.slice == .all)
    #expect(viewModel.state.slice.destination == .record)
  }

  @Test
  func `終點頁只收到 primitive`() throws {
    // 跨 feature 邊界不傳 Domain Model：三個終點頁都不認識 PatientListViewModel.Patient。
    // 這裡直接斷言它們收到的身分資料只由 primitive 組成。
    let viewModel = try makeViewModel(slice: PatientListViewModel.Slice.all.rawValue)

    let record = viewModel.recordViewModel(for: patient).state.patient
    #expect(record == .init(id: "p1", name: "王志明"))

    let encounters = viewModel.encountersViewModel(for: patient).state.patient
    #expect(encounters == .init(id: "p1", name: "王志明"))

    let medications = viewModel.medicationsViewModel(for: patient).state.patient
    #expect(medications == .init(id: "p1", name: "王志明"))

    let vitals = viewModel.detailViewModel(for: patient).state.patient
    #expect(vitals.id == "p1")
    #expect(vitals.name == "王志明")

    for identity in [Mirror(reflecting: record), Mirror(reflecting: encounters), Mirror(reflecting: medications)] {
      for child in identity.children {
        #expect(child.value is String, "身分資料只能由 primitive 組成，卻出現 \(type(of: child.value))")
      }
    }
  }

  @Test
  func `同一位病人重複開啟拿到同一個 ViewModel`() throws {
    // 每次 body 重算就新建一個的話，已載入的資料與捲動位置都會丟失。
    let viewModel = try makeViewModel(slice: PatientListViewModel.Slice.onMedication.rawValue)

    #expect(viewModel.medicationsViewModel(for: patient) === viewModel.medicationsViewModel(for: patient))
    #expect(viewModel.recordViewModel(for: patient) === viewModel.recordViewModel(for: patient))
    #expect(viewModel.encountersViewModel(for: patient) === viewModel.encountersViewModel(for: patient))
  }
}
