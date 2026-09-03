import Foundation
import FHIRCore
import FHIRClient
import SmartAuth

@Observable
@MainActor
final class MainViewModel {

  var state: State = .init()

  @ObservationIgnored
  var onRoute: (@MainActor (Router) -> Void)?

  @ObservationIgnored
  private let client: FHIRClient

  @ObservationIgnored
  private let tokenStore: TokenStore

  init(client: FHIRClient, tokenStore: TokenStore, serverHost: String) {
    self.client = client
    self.tokenStore = tokenStore
    self.state.serverHost = serverHost
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

extension MainViewModel {

  enum Action: Sendable {
    case view(ViewAction)
    case apiRequest(APIRequest)
    case apiResponse(APIResponse)
  }

  enum ViewAction: Sendable {
    case isFirstAppear
    case sliceDidTap(PatientSlice)
    case signOutDidTap
  }

  enum APIRequest: Sendable {
    case loadIdentity
    case loadSliceCount(PatientSlice)
  }

  enum APIResponse: Sendable {
    case identity(Result<IdentityPayload, FHIRClientError>)
    /// 帶的是 bundle（DTO）而非算好的數字——去重與計數是 `handleAPIResponse` 的責任。
    case sliceCount(PatientSlice, Result<FHIR.Bundle, FHIRClientError>)
  }

  enum Router: Sendable {
    case toPatientList(slice: String)
    case toSignOut
  }
}

// MARK: - View Actions

private extension MainViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case .isFirstAppear:
      guard state.isFirstAppear else { return }
      state.isFirstAppear = false
      // 五支查詢各自獨立發出，不互相等待——內容區在任何一支回來之前就要完整可見。
      // 刻意不用 withTaskGroup／async let：那兩者的語意都是「等全部完成」，
      // 而這裡要的是各自抵達、各自更新自己那格狀態。
      Task { await doAction(.apiRequest(.loadIdentity)) }
      for slice in PatientSlice.allCases {
        Task { await doAction(.apiRequest(.loadSliceCount(slice))) }
      }

    case let .sliceDidTap(slice):
      // 跨 feature 邊界只傳 primitive。
      onRoute?(.toPatientList(slice: slice.rawValue))

    case .signOutDidTap:
      await tokenStore.signOut()
      onRoute?(.toSignOut)
    }
  }
}

// MARK: - API Requests

private extension MainViewModel {

  func handleAPIRequest(_ request: APIRequest) async {
    switch request {
    case .loadIdentity:
      guard let reference = await tokenStore.currentTokens?.fhirUser,
            let id = reference.split(separator: "/").last.map(String.init)
      else { return }

      // 先放上 reference——就算兩支查詢都失敗，header 也不會是空的。
      state.practitioner = .init(reference: reference)

      do {
        // 兩支互不相干，併發送出。
        async let practitioner = client.read(FHIR.Practitioner.self, id: id)
        async let roles = client.search(.practitionerRoles(practitionerID: id))
        let payload = IdentityPayload(
          practitioner: try await practitioner,
          roles: try await roles.resources(of: FHIR.PractitionerRole.self)
        )
        await doAction(.apiResponse(.identity(.success(payload))))
      } catch let error as FHIRClientError {
        await doAction(.apiResponse(.identity(.failure(error))))
      } catch {
        await doAction(.apiResponse(.identity(.failure(.transport(message: String(describing: error))))))
      }

    case let .loadSliceCount(slice):
      state.slices[slice]?.status = .loading
      do {
        let bundle = try await client.search(searchFor(slice))
        await doAction(.apiResponse(.sliceCount(slice, .success(bundle))))
      } catch let error as FHIRClientError {
        await doAction(.apiResponse(.sliceCount(slice, .failure(error))))
      } catch {
        await doAction(.apiResponse(.sliceCount(slice, .failure(.transport(message: String(describing: error))))))
      }
    }
  }

  func searchFor(_ slice: PatientSlice) -> FHIRSearch {
    switch slice {
    case .all: .patients()
    case .seenToday: .encountersToday()
    case .outOfRange: .recentVitalSigns()
    case .onMedication: .activeMedicationRequests()
    }
  }
}

// MARK: - API Responses

private extension MainViewModel {

  func handleAPIResponse(_ response: APIResponse) {
    switch response {
    case let .identity(result):
      switch result {
      case let .success(payload):
        guard let reference = state.practitioner?.reference else { return }
        state.practitioner = .init(reference: reference, payload: payload)
      case .failure:
        // 身分顯示不是任務阻斷點：保留只有 reference 的版本，不出現錯誤提示。
        break
      }

    case let .sliceCount(slice, result):
      switch result {
      case let .success(bundle):
        state.slices[slice] = .init(count: .make(from: bundle, slice: slice), status: .success)
      case .failure:
        // 只有這張卡片不可用，其餘不受影響。
        state.slices[slice] = .init(count: nil, status: .unavailable)
      }
    }
  }
}
