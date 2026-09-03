import Foundation
import Testing
import FHIRCore
import FHIRClient
@testable import Tideng

/// MVVMC 的測試哲學：直接以 `doAction(.apiResponse(...))` 注入結果，
/// 不需要 protocol、不需要 mock class、不需要攔截網路。
@MainActor
struct PatientListViewModelTests {

  private func makeViewModel() throws -> PatientListViewModel {
    PatientListViewModel(client: try FHIRClient(baseURL: URL(string: "https://example.org/fhir")!))
  }

  private func decodePatient(_ json: String) throws -> FHIR.Patient {
    try JSONDecoder().decode(FHIR.Patient.self, from: Data(json.utf8))
  }

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
    let patient = try decodePatient("""
    {"resourceType":"Patient","id":"p1","name":[{"family":"王","given":["小明"]}],"gender":"male"}
    """)

    await viewModel.doAction(.apiResponse(.patients(.success([patient]))))

    #expect(viewModel.state.patients.count == 1)
    #expect(viewModel.state.patients.first?.name == "王小明")
    #expect(viewModel.state.patients.first?.gender == .male)
    #expect(viewModel.state.api.loadPatients == .success)
  }

  @Test
  func `沒有 id 的資源被濾掉因為 UI 無法定位它`() async throws {
    let viewModel = try makeViewModel()
    let withID = try decodePatient(#"{"resourceType":"Patient","id":"p1"}"#)
    let withoutID = try decodePatient(#"{"resourceType":"Patient"}"#)

    await viewModel.doAction(.apiResponse(.patients(.success([withID, withoutID]))))

    #expect(viewModel.state.patients.count == 1)
    #expect(viewModel.state.patients.first?.id == "p1")
  }

  @Test
  func `刷新失敗不清空已在畫面上的資料`() async throws {
    let viewModel = try makeViewModel()
    let patient = try decodePatient(#"{"resourceType":"Patient","id":"p1"}"#)
    await viewModel.doAction(.apiResponse(.patients(.success([patient]))))

    await viewModel.doAction(.apiResponse(.patients(.failure(.transport(message: "offline")))))

    #expect(viewModel.state.patients.count == 1)
    guard case .error = viewModel.state.api.loadPatients else {
      Issue.record("預期進入 error 狀態")
      return
    }
  }
}
