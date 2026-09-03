import Foundation
import FHIRCore
import FHIRClient

@Observable
@MainActor
final class PatientListViewModel {

  var state: State = .init()

  @ObservationIgnored
  private let client: FHIRClient

  init(client: FHIRClient) {
    self.client = client
  }

  func doAction(_ action: Action) async {
    switch action {
    case let .view(action):
      await handleViewAction(action)
    case let .apiRequest(request):
      await handleAPIRequest(request)
    case let .apiResponse(response):
      handleAPIResponse(response)
    }
  }
}

// MARK: - Actions

extension PatientListViewModel {

  enum Action: Sendable {
    case view(ViewAction)
    case apiRequest(APIRequest)
    case apiResponse(APIResponse)
  }

  enum ViewAction: Sendable {
    case isFirstAppear
    case pullToRefresh
    case retryDidTap
  }

  enum APIRequest: Sendable {
    case loadPatients
  }

  enum APIResponse: Sendable {
    /// 帶的是 FHIR resource（DTO）而不是 Domain Model——翻譯是 `handleAPIResponse` 的責任。
    case patients(Result<[FHIR.Patient], FHIRClientError>)
  }
}

// MARK: - View Actions

private extension PatientListViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case .isFirstAppear:
      guard state.isFirstAppear else { return }
      state.isFirstAppear = false
      await doAction(.apiRequest(.loadPatients))

    case .pullToRefresh, .retryDidTap:
      await doAction(.apiRequest(.loadPatients))
    }
  }
}

// MARK: - API Requests

private extension PatientListViewModel {

  func handleAPIRequest(_ request: APIRequest) async {
    switch request {
    case .loadPatients:
      state.api.loadPatients = .loading
      do {
        let bundle = try await client.search(.patients())
        let resources = bundle.resources(of: FHIR.Patient.self)
        await doAction(.apiResponse(.patients(.success(resources))))
      } catch let error as FHIRClientError {
        await doAction(.apiResponse(.patients(.failure(error))))
      } catch {
        await doAction(.apiResponse(.patients(.failure(.transport(message: String(describing: error))))))
      }
    }
  }
}

// MARK: - API Responses

private extension PatientListViewModel {

  func handleAPIResponse(_ response: APIResponse) {
    switch response {
    case let .patients(result):
      switch result {
      case let .success(resources):
        // 沒有 id 的 resource 進不了 Domain Model，直接濾掉——那種資料 UI 也定位不到。
        state.patients = resources.compactMap(Patient.init(resource:))
        state.api.loadPatients = .success

      case let .failure(error):
        // 刻意不清空 state.patients：刷新失敗時使用者眼前的清單要留著。
        state.api.loadPatients = .error(message: ErrorMessage.text(for: error))
      }
    }
  }
}
