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
      id: "local-launcher",
      name: String(localized: "Local SMART Launcher"),
      // `sim/e30` 的 e30 是 base64url("{}")，也就是最小的 launch options。
      // 少了 sim 這一段，authorize 會回 "Invalid launch options" —— discovery 卻是通的，
      // 所以問題會拖到按下登入才炸出來。
      baseURL: "http://localhost:8090/v/r4/sim/e30/fhir",
      clientID: "tideng",
      note: String(localized: "The service started by Server/docker-compose.yml")
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
