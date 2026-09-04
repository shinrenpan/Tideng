import Foundation
import FHIRCore
import FHIRClient

@Observable
@MainActor
final class PatientDetailViewModel {

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

extension PatientDetailViewModel {

  enum Action: Sendable {
    case view(ViewAction)
    case apiRequest(APIRequest)
    case apiResponse(APIResponse)
  }

  enum ViewAction: Sendable {
    case isFirstAppear
    case retryDidTap
  }

  enum APIRequest: Sendable {
    case loadVitals
  }

  enum APIResponse: Sendable {
    /// 帶的是解碼結果（DTO）——濾除、分組、排序都是 `handleAPIResponse` 的責任。
    case vitals(Result<FHIRBundleDecoder.Result, FHIRClientError>)
  }
}

// MARK: - View Actions

private extension PatientDetailViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case .isFirstAppear:
      guard state.isFirstAppear else { return }
      state.isFirstAppear = false
      await doAction(.apiRequest(.loadVitals))

    case .retryDidTap:
      await doAction(.apiRequest(.loadVitals))
    }
  }
}

// MARK: - API Requests

private extension PatientDetailViewModel {

  func handleAPIRequest(_ request: APIRequest) async {
    switch request {
    case .loadVitals:
      state.api.loadVitals = .loading
      do {
        let response = try await client.search(.vitalSigns(patientID: state.patient.id))
        await doAction(.apiResponse(.vitals(.success(response))))
      } catch let error as FHIRClientError {
        await doAction(.apiResponse(.vitals(.failure(error))))
      } catch {
        await doAction(.apiResponse(.vitals(.failure(.transport(message: String(describing: error))))))
      }
    }
  }
}

// MARK: - API Responses

private extension PatientDetailViewModel {

  func handleAPIResponse(_ response: APIResponse) {
    switch response {
    case let .vitals(result):
      switch result {
      case let .success(response):
        state.series = VitalSeries.series(from: response.bundle.resources(of: FHIR.Observation.self))
        state.api.loadVitals = .success

      case let .failure(error):
        // 刻意不清空 series：已經畫出來的圖，不因為一次刷新失敗就消失。
        state.api.loadVitals = .error(message: ErrorMessage.text(for: error))
      }
    }
  }
}
