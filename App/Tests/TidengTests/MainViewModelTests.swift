import Foundation
import Testing
import FHIRCore
import FHIRClient
@testable import Tideng

@MainActor
struct MainViewModelTests {

  private func makeViewModel() throws -> MainViewModel {
    MainViewModel(
      client: try TestSupport.makeClient(),
      tokenStore: try TestSupport.makeTokenStore(),
      serverHost: "example.org"
    )
  }

  // MARK: - 初始狀態

  @Test
  func `四個切片初始皆為 prepare 且無計數`() throws {
    let viewModel = try makeViewModel()

    for slice in MainViewModel.PatientSlice.allCases {
      #expect(viewModel.state.slices[slice]?.status == .prepare)
      #expect(viewModel.state.slices[slice]?.count == nil)
    }
  }

  // MARK: - 登入者身分的三段降級

  @Test
  func `姓名與職位都取得時 header 兩行都有內容`() async throws {
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiRequest(.loadIdentity))   // 先放上 reference

    let practitioner = try TestSupport.decode(FHIR.Practitioner.self, """
    { "resourceType": "Practitioner", "id": "137594487",
      "name": [{ "family": "王", "given": ["大明"] }] }
    """)
    let role = try TestSupport.decode(FHIR.PractitionerRole.self, """
    { "resourceType": "PractitionerRole",
      "code": [{ "coding": [{ "code": "158965000", "display": "內科" }] }] }
    """)

    await viewModel.doAction(.apiResponse(.identity(.success(
      .init(practitioner: practitioner, roles: [role])
    ))))

    #expect(viewModel.state.practitioner?.name == "王大明")
    #expect(viewModel.state.practitioner?.role == "內科")
    #expect(viewModel.state.practitioner?.displayName == "王大明")
  }

  @Test
  func `有姓名但沒有職位時 role 為 nil 而不是空字串`() async throws {
    // 空字串會讓 View 畫出一行看不見的空白佔位；nil 才能讓它整行消失。
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiRequest(.loadIdentity))

    let practitioner = try TestSupport.decode(FHIR.Practitioner.self, """
    { "resourceType": "Practitioner", "id": "137594487",
      "name": [{ "family": "陳", "given": ["美玲"] }] }
    """)

    await viewModel.doAction(.apiResponse(.identity(.success(
      .init(practitioner: practitioner, roles: [])
    ))))

    #expect(viewModel.state.practitioner?.name == "陳美玲")
    #expect(viewModel.state.practitioner?.role == nil)
  }

  @Test
  func `查詢失敗時退回顯示 raw reference 而非空白`() async throws {
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiRequest(.loadIdentity))

    await viewModel.doAction(.apiResponse(.identity(.failure(.transport(message: "offline")))))

    // 身分顯示不是任務阻斷點：拿不到姓名就顯示 reference，app 照常可用。
    #expect(viewModel.state.practitioner?.name == nil)
    #expect(viewModel.state.practitioner?.displayName == "Practitioner/137594487")
  }

  @Test
  func `practitioner 資源沒有可用姓名時同樣退回 reference`() async throws {
    // sandbox 上的 Practitioner 資料品質與病人資料一樣差，這不是罕見情況。
    let viewModel = try makeViewModel()
    await viewModel.doAction(.apiRequest(.loadIdentity))

    let nameless = try TestSupport.decode(FHIR.Practitioner.self, """
    { "resourceType": "Practitioner", "id": "137594487" }
    """)

    await viewModel.doAction(.apiResponse(.identity(.success(
      .init(practitioner: nameless, roles: [])
    ))))

    #expect(viewModel.state.practitioner?.displayName == "Practitioner/137594487")
  }

  // MARK: - 計數獨立性

  @Test
  func `注入單一切片的回應時其餘切片維持 prepare`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "total": 38,
      "entry": [ { "resource": { "resourceType": "Patient", "id": "p1" } } ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.all, .success(TestSupport.response(bundle)))))

    #expect(viewModel.state.slices[.all]?.status == .success)
    for slice in MainViewModel.PatientSlice.allCases where slice != .all {
      #expect(viewModel.state.slices[slice]?.status == .prepare)
    }
  }

  @Test
  func `三個計數成功一個失敗時彼此不受影響`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "total": 7 }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.all, .success(TestSupport.response(bundle)))))
    await viewModel.doAction(.apiResponse(.sliceCount(.seenToday, .success(TestSupport.response(bundle)))))
    await viewModel.doAction(.apiResponse(.sliceCount(.onMedication, .success(TestSupport.response(bundle)))))
    await viewModel.doAction(.apiResponse(.sliceCount(.outOfRange, .failure(.transport(message: "timeout")))))

    #expect(viewModel.state.slices[.all]?.status == .success)
    #expect(viewModel.state.slices[.seenToday]?.status == .success)
    #expect(viewModel.state.slices[.onMedication]?.status == .success)

    #expect(viewModel.state.slices[.outOfRange]?.status == .unavailable)
    #expect(viewModel.state.slices[.outOfRange]?.count == nil)

    // 失敗的那個不得把別人的值一起清掉
    #expect(viewModel.state.slices[.all]?.count == .exact(7))
  }

  @Test
  func `計數失敗的切片仍能推進到清單`() async throws {
    // 「卡片仍可點擊」在 VM 層的意義：即使計數取不到，點下去仍會推進。
    // 計數失敗不代表清單本身也會失敗。
    let viewModel = try makeViewModel()

    await viewModel.doAction(.apiResponse(.sliceCount(.outOfRange, .failure(.transport(message: "timeout")))))
    await viewModel.doAction(.view(.sliceDidTap(.outOfRange)))

    #expect(viewModel.state.presentedSlice == .outOfRange)
  }

  @Test
  func `每個切片都能被推進`() async throws {
    let viewModel = try makeViewModel()

    for slice in MainViewModel.PatientSlice.allCases {
      await viewModel.doAction(.view(.sliceDidTap(slice)))
      #expect(viewModel.state.presentedSlice == slice)
    }
  }

  @Test
  func `sliceCards 以固定順序涵蓋全部切片`() throws {
    let viewModel = try makeViewModel()
    #expect(viewModel.state.sliceCards.map(\.slice) == MainViewModel.PatientSlice.allCases)
  }

  @Test
  func `登出發出導航意圖並清除憑證`() async throws {
    let storage = InMemoryTokenStorage()
    let viewModel = MainViewModel(
      client: try TestSupport.makeClient(),
      tokenStore: try TestSupport.makeTokenStore(storage: storage),
      serverHost: "example.org"
    )
    let recorder = RouteRecorder<MainViewModel.Router>()
    viewModel.onRoute = { recorder.record($0) }

    await viewModel.doAction(.view(.signOutDidTap))

    #expect(recorder.last == .toSignOut)
    #expect(storage.isEmpty)
  }

  // MARK: - 精確值 vs 下限值

  @Test
  func `server 給了 total 時計數為精確值`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "total": 38,
      "entry": [ { "resource": { "resourceType": "Patient", "id": "p1" } } ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.all, .success(TestSupport.response(bundle)))))

    #expect(viewModel.state.slices[.all]?.count == .exact(38))
  }

  @Test
  func `server 沒給 total 但還有下一頁時計數為下限值`() async throws {
    // HAPI 公開 server 實測不回 total。此時撈到幾筆只能當下限，
    // 不能當成「總共就這麼多」——那會把 38 位病人報成 2 位。
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset",
      "link": [ { "relation": "next", "url": "https://example.org/fhir/Patient?page=2" } ],
      "entry": [
        { "resource": { "resourceType": "Patient", "id": "p1" } },
        { "resource": { "resourceType": "Patient", "id": "p2" } }
      ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.all, .success(TestSupport.response(bundle)))))

    #expect(viewModel.state.slices[.all]?.count == .atLeast(2))
  }

  @Test
  func `server 沒給 total 且沒有下一頁時計數為精確值`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset",
      "entry": [ { "resource": { "resourceType": "Patient", "id": "p1" } } ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.all, .success(TestSupport.response(bundle)))))

    #expect(viewModel.state.slices[.all]?.count == .exact(1))
  }

  @Test
  func `精確值與下限值是不同的值`() {
    // 若兩者可以相等，UI 就分不出該不該加上「至少」標記。
    #expect(MainViewModel.SliceCount.exact(3) != MainViewModel.SliceCount.atLeast(3))
    #expect(MainViewModel.SliceCount.exact(3).amount == 3)
    #expect(MainViewModel.SliceCount.atLeast(3).amount == 3)
  }

  // MARK: - 依切片去重

  @Test
  func `今日就診依病人去重不是算就診筆數`() async throws {
    // 一位病人可能有多次就診。卡片說的是「幾位病人」，不是「幾筆紀錄」。
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset",
      "entry": [
        { "resource": { "resourceType": "Encounter", "id": "e1", "status": "in-progress",
                        "class": { "code": "AMB" }, "subject": { "reference": "Patient/p1" } } },
        { "resource": { "resourceType": "Encounter", "id": "e2", "status": "in-progress",
                        "class": { "code": "AMB" }, "subject": { "reference": "Patient/p1" } } },
        { "resource": { "resourceType": "Encounter", "id": "e3", "status": "in-progress",
                        "class": { "code": "AMB" }, "subject": { "reference": "Patient/p2" } } }
      ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.seenToday, .success(TestSupport.response(bundle)))))

    #expect(viewModel.state.slices[.seenToday]?.count == .exact(2))
  }

  @Test
  func `用藥中依病人去重`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset",
      "entry": [
        { "resource": { "resourceType": "MedicationRequest", "id": "m1", "status": "active",
                        "intent": "order", "subject": { "reference": "Patient/p1" },
                        "medicationCodeableConcept": { "text": "Amoxicillin 500mg" } } },
        { "resource": { "resourceType": "MedicationRequest", "id": "m2", "status": "active",
                        "intent": "order", "subject": { "reference": "Patient/p1" },
                        "medicationCodeableConcept": { "text": "Paracetamol 500mg" } } }
      ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.onMedication, .success(TestSupport.response(bundle)))))

    #expect(viewModel.state.slices[.onMedication]?.count == .exact(1))
  }

  @Test
  func `超出參考值只計入有 server 參考範圍且落在範圍外的病人`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset",
      "entry": [
        { "resource": { "resourceType": "Observation", "id": "o1", "status": "final",
            "code": { "coding": [{ "code": "8310-5" }] },
            "subject": { "reference": "Patient/p1" },
            "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: 2))",
            "valueQuantity": { "value": 38.9 },
            "referenceRange": [{ "low": { "value": 36.0 }, "high": { "value": 37.5 } }] } },
        { "resource": { "resourceType": "Observation", "id": "o2", "status": "final",
            "code": { "coding": [{ "code": "8310-5" }] },
            "subject": { "reference": "Patient/p2" },
            "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: 2))",
            "valueQuantity": { "value": 37.0 },
            "referenceRange": [{ "low": { "value": 36.0 }, "high": { "value": 37.5 } }] } },
        { "resource": { "resourceType": "Observation", "id": "o3", "status": "final",
            "code": { "coding": [{ "code": "8310-5" }] },
            "subject": { "reference": "Patient/p3" },
            "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: 2))",
            "valueQuantity": { "value": 41.0 } } }
      ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.outOfRange, .success(TestSupport.response(bundle)))))

    // p1 超出；p2 在範圍內；p3 數值很高但 server 沒給範圍——不判讀，不計入
    #expect(viewModel.state.slices[.outOfRange]?.count == .exact(1))
  }

  @Test
  func `server 完全不提供參考範圍時計數為零而非錯誤`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset",
      "entry": [
        { "resource": { "resourceType": "Observation", "id": "o1", "status": "final",
            "code": { "coding": [{ "code": "8310-5" }] },
            "subject": { "reference": "Patient/p1" },
            "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: 2))",
            "valueQuantity": { "value": 41.0 } } }
      ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.outOfRange, .success(TestSupport.response(bundle)))))

    #expect(viewModel.state.slices[.outOfRange]?.count == .exact(0))
    #expect(viewModel.state.slices[.outOfRange]?.status == .success)
  }
}

// MARK: - 部分解碼

@MainActor
struct MainViewModelPartialDecodeTests {

  private func makeViewModel() throws -> MainViewModel {
    MainViewModel(
      client: try TestSupport.makeClient(),
      tokenStore: try TestSupport.makeTokenStore(),
      serverHost: "example.org"
    )
  }

  @Test
  func `去重推導的計數在有 entry 被跳過時降級為下限值`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset",
      "entry": [
        { "resource": { "resourceType": "Encounter", "id": "e1", "status": "in-progress",
                        "class": { "code": "AMB" }, "subject": { "reference": "Patient/p1" } } }
      ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.seenToday, .success(
      TestSupport.response(bundle, skipped: 9)
    ))))

    #expect(viewModel.state.slices[.seenToday]?.count == .atLeast(1))
  }

  @Test
  func `server 給的 total 不因本地解碼失敗而降級`() async throws {
    // total 講的是 server 有多少資料，不是我們解得開多少。
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "total": 307,
      "entry": [ { "resource": { "resourceType": "Patient", "id": "p1" } } ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.all, .success(
      TestSupport.response(bundle, skipped: 1)
    ))))

    #expect(viewModel.state.slices[.all]?.count == .exact(307))
  }

  @Test
  func `全部 entry 都解不出來時報為不可用而非零`() async throws {
    // 報 0 會與「這個 server 真的沒有」無從分辨。
    let viewModel = try makeViewModel()
    let empty = try TestSupport.bundle(#"{ "resourceType": "Bundle", "type": "searchset" }"#)

    await viewModel.doAction(.apiResponse(.sliceCount(.outOfRange, .success(
      TestSupport.response(empty, skipped: 12)
    ))))

    #expect(viewModel.state.slices[.outOfRange]?.status == .unavailable)
    #expect(viewModel.state.slices[.outOfRange]?.count == nil)
  }
}

// MARK: - 計數的語意

@MainActor
struct SliceCountSemanticsTests {

  @Test
  func `下限值與精確值不相等即使數字相同`() {
    #expect(MainViewModel.SliceCount.exact(3) != MainViewModel.SliceCount.atLeast(3))
  }

  @Test
  func `下限值標記得出來`() {
    #expect(MainViewModel.SliceCount.atLeast(3).isLowerBound)
    #expect(MainViewModel.SliceCount.exact(3).isLowerBound == false)
  }

  @Test
  func `至少零不帶任何資訊`() {
    // 「至少 0」與「完全沒有資訊」等價——View 據此不以數字呈現它。
    let noInformation = MainViewModel.SliceCount.atLeast(0)
    #expect(noInformation.amount == 0)
    #expect(noInformation.isLowerBound)
    #expect(noInformation != .exact(0))
  }
}

// MARK: - 身分查詢的獨立容錯

@MainActor
struct PractitionerIdentityResilienceTests {

  @Test
  func `server 沒有 PractitionerRole 時姓名仍然顯示`() throws {
    // Siming 不支援 PractitionerRole（打過去 404）。那支查詢失敗不該讓姓名一起消失——
    // 兩者綁在同一個 do-catch 曾經導致這個結果。
    let practitioner = try TestSupport.decode(FHIR.Practitioner.self, """
    { "resourceType": "Practitioner", "id": "137594487",
      "name": [{ "family": "王", "given": ["大明"] }] }
    """)

    let identity = MainViewModel.PractitionerIdentity(
      reference: "Practitioner/137594487",
      payload: .init(practitioner: practitioner, roles: [])
    )

    #expect(identity.name == "王大明")
    #expect(identity.role == nil)
    #expect(identity.displayName == "王大明")
  }

  @Test
  func `姓名查詢失敗但有角色時仍退回 reference`() {
    let identity = MainViewModel.PractitionerIdentity(
      reference: "Practitioner/137594487",
      payload: .init(practitioner: nil, roles: [])
    )

    #expect(identity.name == nil)
    #expect(identity.displayName == "Practitioner/137594487")
  }
}

// MARK: - 時間窗必須由 client 自己守住

@MainActor
struct OutOfRangeTimeWindowTests {

  private func makeViewModel() throws -> MainViewModel {
    MainViewModel(
      client: try TestSupport.makeClient(),
      tokenStore: try TestSupport.makeTokenStore(),
      serverHost: "example.org"
    )
  }

  private func observation(patient: String, hoursAgo: Double) -> String {
    """
    { "resource": { "resourceType": "Observation", "id": "o-\(patient)", "status": "final",
        "code": { "coding": [{ "code": "8310-5" }] },
        "subject": { "reference": "Patient/\(patient)" },
        "effectiveDateTime": "\(TestSupport.iso8601(hoursAgo: hoursAgo))",
        "valueQuantity": { "value": 38.9 },
        "referenceRange": [{ "low": { "value": 36.0 }, "high": { "value": 37.5 } }] } }
    """
  }

  @Test
  func `時間窗外的觀測值不計入即使超出參考範圍`() async throws {
    // server 可能無視 date 參數（實測 Siming 就是如此：參數在白名單裡、
    // strict 模式不報錯，但過濾完全沒套用）。卡片宣告了「近 24 小時」，
    // 那個宣告必須由 client 自己守住。
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "entry": [
      \(observation(patient: "p1", hoursAgo: 2)),
      \(observation(patient: "p2", hoursAgo: 100))
    ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.outOfRange, .success(TestSupport.response(bundle)))))

    // p2 的體溫同樣超出範圍，但那是 100 小時前的事
    #expect(viewModel.state.slices[.outOfRange]?.count == .exact(1))
  }

  @Test
  func `沒有時間資訊的觀測值不計入`() async throws {
    let viewModel = try makeViewModel()
    let bundle = try TestSupport.bundle("""
    { "resourceType": "Bundle", "type": "searchset", "entry": [
      { "resource": { "resourceType": "Observation", "id": "o1", "status": "final",
          "code": { "coding": [{ "code": "8310-5" }] },
          "subject": { "reference": "Patient/p1" },
          "valueQuantity": { "value": 38.9 },
          "referenceRange": [{ "low": { "value": 36.0 }, "high": { "value": 37.5 } }] } }
    ] }
    """)

    await viewModel.doAction(.apiResponse(.sliceCount(.outOfRange, .success(TestSupport.response(bundle)))))

    // 寧可少算，也不要把不知道時間的資料算進一個宣稱了時間範圍的數字
    #expect(viewModel.state.slices[.outOfRange]?.count == .exact(0))
  }
}
