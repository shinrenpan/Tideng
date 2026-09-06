import Foundation
import FHIRCore
import FHIRClient

@Observable
@MainActor
final class PatientListViewModel {

  var state: State = .init()

  @ObservationIgnored
  private let client: FHIRClient

  /// 已開啟過的終點頁，依病人 id 快取。
  ///
  /// 病人數量不定，無法像主畫面那樣由 HostController 預先建好全部；而每次 body 重算
  /// 就新建一個的話，捲動位置與已載入的資料都會丟失。
  /// 這不是業務邏輯，是子 feature 的組裝——所以不走 `doAction`。
  ///
  /// 一份清單只通往一種終點（終點由切片決定），所以四份快取裡實際只會用到一份。
  @ObservationIgnored
  private var recordViewModels: [String: PatientRecordViewModel] = [:]
  @ObservationIgnored
  private var encounterViewModels: [String: PatientEncountersViewModel] = [:]
  @ObservationIgnored
  private var medicationViewModels: [String: PatientMedicationsViewModel] = [:]
  @ObservationIgnored
  private var detailViewModels: [String: PatientDetailViewModel] = [:]

  /// - Parameter sliceIdentifier: 主畫面傳來的切片識別碼（primitive，不是 Domain Model）。
  init(client: FHIRClient, sliceIdentifier: String = PatientListViewModel.Slice.all.rawValue) {
    self.client = client
    self.state.slice = .init(identifier: sliceIdentifier)
  }

  /// 取得（必要時建立）該病人病歷頁的 ViewModel。
  ///
  /// 跨 feature 邊界只傳 primitive——終點頁不認識這裡的 `Patient` 型別。
  func recordViewModel(for patient: Patient) -> PatientRecordViewModel {
    if let existing = recordViewModels[patient.id] { return existing }
    let viewModel = PatientRecordViewModel(
      client: client,
      patient: .init(id: patient.id, name: patient.name)
    )
    recordViewModels[patient.id] = viewModel
    return viewModel
  }

  /// 取得（必要時建立）該病人就診頁的 ViewModel。
  func encountersViewModel(for patient: Patient) -> PatientEncountersViewModel {
    if let existing = encounterViewModels[patient.id] { return existing }
    let viewModel = PatientEncountersViewModel(
      client: client,
      patient: .init(id: patient.id, name: patient.name)
    )
    encounterViewModels[patient.id] = viewModel
    return viewModel
  }

  /// 取得（必要時建立）該病人用藥頁的 ViewModel。
  func medicationsViewModel(for patient: Patient) -> PatientMedicationsViewModel {
    if let existing = medicationViewModels[patient.id] { return existing }
    let viewModel = PatientMedicationsViewModel(
      client: client,
      patient: .init(id: patient.id, name: patient.name)
    )
    medicationViewModels[patient.id] = viewModel
    return viewModel
  }

  /// 取得（必要時建立）該病人數值趨勢頁的 ViewModel。
  func detailViewModel(for patient: Patient) -> PatientDetailViewModel {
    if let existing = detailViewModels[patient.id] {
      return existing
    }
    let viewModel = PatientDetailViewModel(
      client: client,
      // 跨 feature 邊界只傳 primitive——詳情頁不認識這裡的 Patient 型別
      patient: .init(
        id: patient.id,
        name: patient.name,
        gender: nil,
        age: patient.age,
        recordNumber: patient.recordNumber
      )
    )
    detailViewModels[patient.id] = viewModel
    return viewModel
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
    case patientDidTap(Patient)
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

    case let .patientDidTap(patient):
      state.presentedPatient = patient
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
        let response = try await client.search(state.slice.search, maxPages: state.slice.maxPages)
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
