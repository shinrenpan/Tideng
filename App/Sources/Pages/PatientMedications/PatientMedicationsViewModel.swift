import Foundation
import FHIRCore
import FHIRClient

@Observable
@MainActor
final class PatientMedicationsViewModel {

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

extension PatientMedicationsViewModel {

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
    case loadPrescriptions
  }

  enum APIResponse: Sendable {
    case prescriptions(Result<FHIRBundleDecoder.Result, FHIRClientError>)
  }
}

// MARK: - View Actions

private extension PatientMedicationsViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case .isFirstAppear:
      guard state.isFirstAppear else { return }
      state.isFirstAppear = false
      await doAction(.apiRequest(.loadPrescriptions))

    case .pullToRefresh, .retryDidTap:
      await doAction(.apiRequest(.loadPrescriptions))
    }
  }
}

// MARK: - API Requests

private extension PatientMedicationsViewModel {

  func handleAPIRequest(_ request: APIRequest) async {
    switch request {
    case .loadPrescriptions:
      state.api.loadPrescriptions = .loading
      do {
        let response = try await client.search(.medicationRequests(patientID: state.patient.id))
        await doAction(.apiResponse(.prescriptions(.success(response))))
      } catch let error as FHIRClientError {
        await doAction(.apiResponse(.prescriptions(.failure(error))))
      } catch {
        await doAction(.apiResponse(.prescriptions(.failure(.transport(message: String(describing: error))))))
      }
    }
  }
}

// MARK: - API Responses

private extension PatientMedicationsViewModel {

  func handleAPIResponse(_ response: APIResponse) {
    switch response {
    case let .prescriptions(result):
      switch result {
      case let .success(response):
        state.prescriptions = Self.prescriptions(from: response.bundle)
        state.api.loadPrescriptions = .success

      case let .failure(error):
        // 刻意不清空：刷新失敗時使用者眼前的處方要留著。
        state.api.loadPrescriptions = .error(message: ErrorMessage.text(for: error))
      }
    }
  }
}
