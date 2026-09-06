import Foundation

// MARK: - State

extension ServerSetupViewModel {

  struct State: Equatable, Sendable {
    var baseURLText: String = ""
    var clientIDText: String = "tideng"
    /// client_id 收在進階區——多數使用者不需要改它。
    var isAdvancedExpanded: Bool = false
    var presets: [ServerPreset] = ServerPreset.builtIn
    var api: API = .init()

    var canSignIn: Bool {
      guard api.signIn != .loading else { return false }
      return !baseURLText.trimmingCharacters(in: .whitespaces).isEmpty
        && !clientIDText.trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  struct API: Equatable, Sendable {
    var signIn: Status = .prepare
  }

  enum Status: Equatable, Sendable {
    case prepare
    case loading
    case success
    case error(message: String)
  }
}

// MARK: - Domain Models

extension ServerSetupViewModel {

  /// 內建的伺服器設定。
  ///
  /// demo 時不用手打一長串 URL，也讓「同一個 app 接不同 server」這件事在畫面上就看得到。
  struct ServerPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let baseURL: String
    let clientID: String
    let note: String
  }
}

extension ServerSetupViewModel.ServerPreset {

  static let builtIn: [Self] = [
    .init(
      id: "local-siming",
      name: String(localized: "Local Siming"),
      // 直接指向 Siming，不再經過 smart-launcher-v2 的代理。
      //
      // 授權伺服器改由 Keycloak 擔任，位址寫在 Siming 的
      // `.well-known/smart-configuration` 裡，由 app 從 discovery 取得——
      // 所以這裡不需要（也不該）知道 Keycloak 在哪。
      //
      // 尾斜線很重要：這個字串會原樣成為 authorize 請求的 `aud` 參數，
      // 而 server 端的比對是完全字串相等，多一個斜線就是「token 有效但每個
      // 請求都 401」。它必須與 Siming 的 SMART_AUDIENCE 逐字元相同。
      baseURL: "http://localhost:8080",
      clientID: "tideng",
      note: String(localized: "Local Siming with demo data, signing in through Keycloak")
    ),
    .init(
      id: "smart-sandbox",
      name: String(localized: "SMART public sandbox"),
      baseURL: "https://launch.smarthealthit.org/v/r4/sim/e30/fhir",
      clientID: "tideng",
      note: String(localized: "Check compatibility with external servers")
    )
  ]
}
