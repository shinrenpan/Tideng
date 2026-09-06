import Foundation
import FHIRCore
import FHIRClient

@Observable
@MainActor
final class PatientRecordViewModel {

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

extension PatientRecordViewModel {

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
    case loadRecord
  }

  enum APIResponse: Sendable {
    case record(Result<FHIRBundleDecoder.Result, FHIRClientError>)
  }
}

// MARK: - View Actions

private extension PatientRecordViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case .isFirstAppear:
      guard state.isFirstAppear else { return }
      state.isFirstAppear = false
      await doAction(.apiRequest(.loadRecord))

    case .pullToRefresh, .retryDidTap:
      await doAction(.apiRequest(.loadRecord))
    }
  }
}

// MARK: - API Requests

private extension PatientRecordViewModel {

  func handleAPIRequest(_ request: APIRequest) async {
    switch request {
    case .loadRecord:
      state.api.loadRecord = .loading
      do {
        let response = try await client.search(.patient(id: state.patient.id))
        await doAction(.apiResponse(.record(.success(response))))
      } catch let error as FHIRClientError {
        await doAction(.apiResponse(.record(.failure(error))))
      } catch {
        await doAction(.apiResponse(.record(.failure(.transport(message: String(describing: error))))))
      }
    }
  }
}

// MARK: - API Responses

private extension PatientRecordViewModel {

  func handleAPIResponse(_ response: APIResponse) {
    switch response {
    case let .record(result):
      switch result {
      case let .success(response):
        // 查的是 `_id`，回應理應只有一筆。真的沒有時保持 `record` 為 nil，
        // 由 UI 說「沒有這筆記錄」——不是失敗，是 server 真的沒有。
        state.record = response.bundle.resources(of: FHIR.Patient.self).first.map(Record.init(resource:))
        state.api.loadRecord = .success

      case let .failure(error):
        // 刻意不清空 record：刷新失敗時使用者眼前的資料要留著。
        state.api.loadRecord = .error(message: ErrorMessage.text(for: error))
      }
    }
  }
}
