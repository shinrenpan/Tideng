import Foundation
import FHIRCore
import FHIRClient

@Observable
@MainActor
final class PatientEncountersViewModel {

  var state: State

  @ObservationIgnored
  private let client: FHIRClient

  init(client: FHIRClient, patient: PatientIdentity) {
    self.client = client
    self.state = State(patient: patient)
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

extension PatientEncountersViewModel {

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
    case loadEncounters
  }

  enum APIResponse: Sendable {
    case encounters(Result<FHIRBundleDecoder.Result, FHIRClientError>)
  }
}

// MARK: - View Actions

private extension PatientEncountersViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case .isFirstAppear:
      guard state.isFirstAppear else { return }
      state.isFirstAppear = false
      await doAction(.apiRequest(.loadEncounters))

    case .pullToRefresh, .retryDidTap:
      await doAction(.apiRequest(.loadEncounters))
    }
  }
}

// MARK: - API Requests

private extension PatientEncountersViewModel {

  func handleAPIRequest(_ request: APIRequest) async {
    switch request {
    case .loadEncounters:
      state.api.loadEncounters = .loading
      do {
        let response = try await client.search(.encounters(patientID: state.patient.id))
        await doAction(.apiResponse(.encounters(.success(response))))
      } catch let error as FHIRClientError {
        await doAction(.apiResponse(.encounters(.failure(error))))
      } catch {
        await doAction(.apiResponse(.encounters(.failure(.transport(message: String(describing: error))))))
      }
    }
  }
}

// MARK: - API Responses

private extension PatientEncountersViewModel {

  func handleAPIResponse(_ response: APIResponse) {
    switch response {
    case let .encounters(result):
      switch result {
      case let .success(response):
        state.encounters = Self.encounters(from: response.bundle)
        state.api.loadEncounters = .success

      case let .failure(error):
        // 刻意不清空：刷新失敗時使用者眼前的清單要留著。
        state.api.loadEncounters = .error(message: ErrorMessage.text(for: error))
      }
    }
  }
}
