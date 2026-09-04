import Foundation
import Testing
import FHIRCore
import FHIRClient
@testable import Tideng

@MainActor
struct PatientDetailViewModelTests {

  private let identity = PatientDetailViewModel.PatientIdentity(
    id: "p1", name: "王志明", gender: "男", age: 68, recordNumber: "A0000001"
  )

  private func makeViewModel() throws -> PatientDetailViewModel {
    PatientDetailViewModel(client: try TestSupport.makeClient(), patient: identity)
  }

  /// 一筆體溫觀測值。`hoursAgo` 決定時間，`range` 為 nil 表示 server 沒給參考範圍。
  private func temperature(id: String, hoursAgo: Double, value: Double, withRange: Bool = true) -> String {
    let range = withRange
      ? #", "referenceRange": [{ "low": { "value": 36.0, "unit": "°C" }, "high": { "value": 37.5, "unit": "°C" } }]"#
      : ""
    return """
    { "resource": { "resourceType": "Observation", "id": "\(id)", "status": "final",
        "code": { "coding": [{ "system": "http://loinc.org", "code": "8310-5", "display": "體溫" }] },
        "subject": { "reference": "Patient/p1" },
        "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: hoursAgo))",
        "valueQuantity": { "value": \(value), "unit": "°C", "code": "Cel" }\(range) } }
    """
  }

  private func bundle(_ entries: [String]) throws -> FHIRBundleDecoder.Result {
    TestSupport.response(try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "entry": [\(entries.joined(separator: ","))] }
    """))
  }

  // MARK: - 排序

  @Test
  func `亂序回應被依時間排序`() async throws {
    // server 的排序不可信：Siming 的 _sort 白名單不含 date，未知欄位靜默丟棄。
    // 折線圖依賴點的順序——順序錯了看起來像資料壞掉，而不是排序壞掉。
    let viewModel = try makeViewModel()
    let response = try bundle([
      temperature(id: "o2", hoursAgo: 9, value: 37.0),
      temperature(id: "o1", hoursAgo: 45, value: 36.5),
      temperature(id: "o3", hoursAgo: 3, value: 38.2)
    ])

    await viewModel.doAction(.apiResponse(.vitals(.success(response))))

    let series = try #require(viewModel.state.series.first)
    let times = series.points.map(\.recordedAt)
    #expect(times == times.sorted())
    #expect(series.points.map(\.value) == [36.5, 37.0, 38.2])
  }

  // MARK: - 濾除不可繪製的資料

  @Test
  func `缺少數值或時間的觀測值被濾除`() async throws {
    let viewModel = try makeViewModel()
    let response = try bundle([
      temperature(id: "ok", hoursAgo: 2, value: 37.1),
      // 沒有 valueQuantity
      """
      { "resource": { "resourceType": "Observation", "id": "noValue", "status": "final",
          "code": { "coding": [{ "code": "8310-5", "display": "體溫" }] },
          "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: 4))" } }
      """,
      // 沒有 effective
      """
      { "resource": { "resourceType": "Observation", "id": "noTime", "status": "final",
          "code": { "coding": [{ "code": "8310-5", "display": "體溫" }] },
          "valueQuantity": { "value": 37.3, "unit": "°C" } } }
      """
    ])

    await viewModel.doAction(.apiResponse(.vitals(.success(response))))

    // 一個點需要兩個座標，缺任一個都畫不出來
    let series = try #require(viewModel.state.series.first)
    #expect(series.points.count == 1)
    #expect(series.points.first?.value == 37.1)
  }

  @Test
  func `某種類全部不可繪製時該種類不出現`() async throws {
    let viewModel = try makeViewModel()
    let response = try bundle(["""
      { "resource": { "resourceType": "Observation", "id": "noTime", "status": "final",
          "code": { "coding": [{ "code": "8310-5", "display": "體溫" }] },
          "valueQuantity": { "value": 37.3 } } }
      """])

    await viewModel.doAction(.apiResponse(.vitals(.success(response))))

    // 不畫空圖
    #expect(viewModel.state.series.isEmpty)
  }

  // MARK: - 分組

  @Test
  func `依種類分組並各自帶單位`() async throws {
    let viewModel = try makeViewModel()
    let response = try bundle([
      temperature(id: "t1", hoursAgo: 2, value: 37.1),
      """
      { "resource": { "resourceType": "Observation", "id": "h1", "status": "final",
          "code": { "coding": [{ "system": "http://loinc.org", "code": "8867-4", "display": "心跳速率" }] },
          "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: 2))",
          "valueQuantity": { "value": 78, "unit": "次/分", "code": "/min" } } }
      """
    ])

    await viewModel.doAction(.apiResponse(.vitals(.success(response))))

    #expect(viewModel.state.series.count == 2)
    let byCode = Dictionary(uniqueKeysWithValues: viewModel.state.series.map { ($0.code, $0) })
    #expect(byCode["8310-5"]?.unit == "°C")
    #expect(byCode["8867-4"]?.unit == "次/分")
  }

  @Test
  func `單一觀測值仍成立為一個點`() async throws {
    let viewModel = try makeViewModel()
    let response = try bundle([temperature(id: "only", hoursAgo: 1, value: 36.9)])

    await viewModel.doAction(.apiResponse(.vitals(.success(response))))

    #expect(viewModel.state.series.first?.points.count == 1)
  }

  // MARK: - 參考範圍

  @Test
  func `server 有給參考範圍時帶進 series`() async throws {
    let viewModel = try makeViewModel()
    let response = try bundle([temperature(id: "t1", hoursAgo: 2, value: 38.8)])

    await viewModel.doAction(.apiResponse(.vitals(.success(response))))

    let bounds = try #require(viewModel.state.series.first?.referenceRange)
    #expect(bounds.low == 36.0)
    #expect(bounds.high == 37.5)
  }

  @Test
  func `server 沒給參考範圍時為 nil 而非套用內建值`() async throws {
    // 沒有範圍就不畫帶子。套用內建值等於由 app 定義何謂正常，那是臨床判讀。
    let viewModel = try makeViewModel()
    let response = try bundle([temperature(id: "t1", hoursAgo: 2, value: 38.8, withRange: false)])

    await viewModel.doAction(.apiResponse(.vitals(.success(response))))

    #expect(viewModel.state.series.first?.referenceRange == nil)
    // 而且值仍然照常呈現——不因為沒有範圍就藏起來
    #expect(viewModel.state.series.first?.points.first?.value == 38.8)
  }
}

// MARK: - 四態與身分資料

@MainActor
struct PatientDetailStateTests {

  private func makeViewModel(
    patient: PatientDetailViewModel.PatientIdentity = .init(
      id: "p1", name: "王志明", gender: "男", age: 68, recordNumber: "A0000001"
    )
  ) throws -> PatientDetailViewModel {
    PatientDetailViewModel(client: try TestSupport.makeClient(), patient: patient)
  }

  private func observationBundle(_ count: Int) throws -> FHIRBundleDecoder.Result {
    let entries = (0..<count).map { index in
      """
      { "resource": { "resourceType": "Observation", "id": "o\(index)", "status": "final",
          "code": { "coding": [{ "code": "8310-5", "display": "體溫" }] },
          "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: Double(index)))",
          "valueQuantity": { "value": 37.0, "unit": "°C" } } }
      """
    }
    return TestSupport.response(try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "entry": [\(entries.joined(separator: ","))] }
    """))
  }

  @Test
  func `初始為尚未載入`() throws {
    let viewModel = try makeViewModel()
    #expect(viewModel.state.series.isEmpty)
    #expect(viewModel.state.api.loadVitals == .prepare)
  }

  @Test
  func `載入成功但沒有紀錄`() async throws {
    // 這一態必須與「還在載入」分得開，否則畫面會一直轉圈
    let viewModel = try makeViewModel()
    let empty = TestSupport.response(try TestSupport.bundle(#"{ "resourceType": "Bundle", "type": "searchset" }"#))

    await viewModel.doAction(.apiResponse(.vitals(.success(empty))))

    #expect(viewModel.state.series.isEmpty)
    #expect(viewModel.state.api.loadVitals == .success)
  }

  @Test
  func `首次載入失敗時帶著訊息`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.vitals(.failure(.transport(message: "offline")))))

    #expect(viewModel.state.series.isEmpty)
    guard case let .error(message) = viewModel.state.api.loadVitals else {
      Issue.record("預期進入 error 狀態")
      return
    }
    #expect(!message.isEmpty)
  }

  @Test
  func `已有圖時刷新失敗不清空`() async throws {
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiResponse(.vitals(.success(try observationBundle(3)))))

    await viewModel.doAction(.apiResponse(.vitals(.failure(.transport(message: "offline")))))

    // 已經畫出來的圖不該因為一次刷新失敗就消失
    #expect(viewModel.state.series.first?.points.count == 3)
    guard case .error = viewModel.state.api.loadVitals else {
      Issue.record("預期進入 error 狀態")
      return
    }
  }

  @Test
  func `身分資料原樣呈現不重新解讀`() throws {
    let viewModel = try makeViewModel()
    #expect(viewModel.state.patient.name == "王志明")
    #expect(viewModel.state.patient.age == 68)
    #expect(viewModel.state.patient.recordNumber == "A0000001")
  }

  @Test
  func `缺漏的身分欄位為 nil 讓 View 整段省略`() throws {
    let viewModel = try makeViewModel(
      patient: .init(id: "p9", name: "Unnamed", gender: nil, age: nil, recordNumber: nil)
    )
    #expect(viewModel.state.patient.age == nil)
    #expect(viewModel.state.patient.recordNumber == nil)
    #expect(viewModel.state.patient.gender == nil)
  }

  @Test
  func `run once 旗標擋掉重複觸發`() async throws {
    let viewModel = try makeViewModel()
    viewModel.state.isFirstAppear = false

    await viewModel.doAction(.view(.isFirstAppear))

    #expect(viewModel.state.api.loadVitals == .prepare)
  }
}

// MARK: - 從清單推進到詳情

@MainActor
struct PatientListNavigationTests {

  private func makeViewModel() throws -> PatientListViewModel {
    PatientListViewModel(client: try TestSupport.makeClient())
  }

  private func patient(id: String = "p1") -> PatientListViewModel.Patient {
    .init(id: id, name: "王小明", gender: .male, birthDate: DateComponents(year: 1958), recordNumber: "A0000001")
  }

  @Test
  func `點選病人後推進到該病人`() async throws {
    let viewModel = try makeViewModel()

    await viewModel.doAction(.view(.patientDidTap(patient())))

    #expect(viewModel.state.presentedPatient == patient())
  }

  @Test
  func `詳情的 ViewModel 以 primitive 建構且身分資料一致`() throws {
    let viewModel = try makeViewModel()

    let detail = viewModel.detailViewModel(for: patient())

    #expect(detail.state.patient.id == "p1")
    #expect(detail.state.patient.name == "王小明")
    #expect(detail.state.patient.recordNumber == "A0000001")
  }

  @Test
  func `同一位病人重複取得的是同一個 ViewModel`() throws {
    // 每次 body 重算就新建一個的話，捲動位置與已載入的觀測值都會丟失
    let viewModel = try makeViewModel()

    let first = viewModel.detailViewModel(for: patient())
    let second = viewModel.detailViewModel(for: patient())

    #expect(first === second)
  }

  @Test
  func `不同病人取得不同的 ViewModel`() throws {
    let viewModel = try makeViewModel()

    let one = viewModel.detailViewModel(for: patient(id: "p1"))
    let other = viewModel.detailViewModel(for: patient(id: "p2"))

    #expect(one !== other)
  }
}
