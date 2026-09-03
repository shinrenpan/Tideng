import Foundation
import FHIRCore
import FHIRClient

@Observable
@MainActor
final class PatientListViewModel {

  var state: State = .init()

  @ObservationIgnored
  private let client: FHIRClient

  /// - Parameter sliceIdentifier: 主畫面傳來的切片識別碼（primitive，不是 Domain Model）。
  init(client: FHIRClient, sliceIdentifier: String = PatientListViewModel.Slice.all.rawValue) {
    self.client = client
    self.state.slice = .init(identifier: sliceIdentifier)
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
    /// 帶的是解碼結果（DTO）而不是 Domain Model——挑出病人與翻譯都是
    /// `handleAPIResponse` 的責任。切片不同，挑法也不同。
    case patients(Result<FHIRBundleDecoder.Result, FHIRClientError>)
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
        let response = try await client.search(state.slice.search)
        await doAction(.apiResponse(.patients(.success(response))))
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
      case let .success(response):
        // 沒有 id 的 resource 進不了 Domain Model，直接濾掉——那種資料 UI 也定位不到。
        state.patients = state.slice.patients(from: response.bundle).compactMap(Patient.init(resource:))
        state.api.loadPatients = .success

      case let .failure(error):
        // 刻意不清空 state.patients：刷新失敗時使用者眼前的清單要留著。
        state.api.loadPatients = .error(message: ErrorMessage.text(for: error))
      }
    }
  }
}
