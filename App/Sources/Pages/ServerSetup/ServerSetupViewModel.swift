import Foundation
import SmartAuth

@Observable
@MainActor
final class ServerSetupViewModel {

  var state: State = .init()

  @ObservationIgnored
  var onRoute: (@MainActor (Router) -> Void)?

  @ObservationIgnored
  private let coordinator: SmartLoginCoordinator

  init(coordinator: SmartLoginCoordinator = SmartLoginCoordinator()) {
    self.coordinator = coordinator
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

extension ServerSetupViewModel {

  enum Action: Sendable {
    case view(ViewAction)
    case apiRequest(APIRequest)
    case apiResponse(APIResponse)
  }

  enum ViewAction: Sendable {
    case presetDidTap(id: String)
    case signInDidTap
  }

  enum APIRequest: Sendable {
    case signIn
  }

  enum APIResponse: Sendable {
    case signIn(SignInOutcome)
  }

  /// 登入結果。
  ///
  /// 不用 `Result<TokenStore, SmartAuthError>`：TokenStore 是 actor，塞進 `Result` 會讓
  /// 整個 Action enum 失去 Equatable，而 Action 的可比較性在測試裡有用。
  enum SignInOutcome: Sendable {
    case success(baseURL: URL, store: TokenStore)
    case failure(SmartAuthError)
  }

  /// 不加 `Equatable`：`TokenStore` 是 actor，無法合成。
  /// 導航意圖本身在測試中以 case 比對即可。
  enum Router: Sendable {
    case toMain(baseURL: URL, store: TokenStore)
  }
}

// MARK: - View Actions

private extension ServerSetupViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case let .presetDidTap(id):
      guard let preset = state.presets.first(where: { $0.id == id }) else { return }
      state.baseURLText = preset.baseURL
      state.clientIDText = preset.clientID
      state.api.signIn = .prepare

    case .signInDidTap:
      guard state.canSignIn else { return }
      await doAction(.apiRequest(.signIn))
    }
  }
}

// MARK: - API Requests

private extension ServerSetupViewModel {

  func handleAPIRequest(_ request: APIRequest) async {
    switch request {
    case .signIn:
      guard let baseURL = normalisedBaseURL() else {
        await doAction(.apiResponse(.signIn(.failure(
          .discoveryFailed(reason: String(localized: "That doesn't look like a valid server address."))
        ))))
        return
      }

      state.api.signIn = .loading
      do {
        let store = try await coordinator.signIn(
          fhirBaseURL: baseURL,
          clientID: state.clientIDText.trimmingCharacters(in: .whitespaces),
          redirectURI: AppConfiguration.redirectURI,
          scopes: AppConfiguration.scopes,
          profileID: baseURL.absoluteString
        )
        await doAction(.apiResponse(.signIn(.success(baseURL: baseURL, store: store))))
      } catch let error as SmartAuthError {
        await doAction(.apiResponse(.signIn(.failure(error))))
      } catch {
        await doAction(.apiResponse(.signIn(.failure(.transport(message: String(describing: error))))))
      }
    }
  }

  /// 使用者輸入的網址是不受信任輸入：去空白、補 scheme、擋掉非 http(s)。
  func normalisedBaseURL() -> URL? {
    var text = state.baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    // 沒填 scheme 時補 https——比直接報錯友善，而且不會把 http 悄悄升級成使用者沒要求的東西。
    if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
      text = "https://" + text
    }
    // 尾端斜線會讓後續 appendingPathComponent 組出雙斜線，有些 server 會 404。
    while text.hasSuffix("/") {
      text.removeLast()
    }

    guard let url = URL(string: text),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          url.host != nil
    else { return nil }

    return url
  }
}

// MARK: - API Responses

private extension ServerSetupViewModel {

  func handleAPIResponse(_ response: APIResponse) {
    switch response {
    case let .signIn(outcome):
      switch outcome {
      case let .success(baseURL, store):
        state.api.signIn = .success
        onRoute?(.toMain(baseURL: baseURL, store: store))

      case let .failure(error):
        // 使用者自己取消不算錯誤，畫面回到可以再按一次的狀態就好。
        state.api.signIn = error == .userCancelled
          ? .prepare
          : .error(message: ErrorMessage.text(for: error))
      }
    }
  }
}
