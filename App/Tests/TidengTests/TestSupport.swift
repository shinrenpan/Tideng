import Foundation
import FHIRCore
import FHIRClient
import SmartAuth

/// 測試用的憑證儲存：要驗的是 ViewModel 的狀態轉移，不是 Keychain。
final class InMemoryTokenStorage: TokenPersisting, @unchecked Sendable {

  private let lock = NSLock()
  private var stored: [String: TokenSet] = [:]

  init(seed: TokenSet? = nil, profileID: String = "test") {
    if let seed { stored[profileID] = seed }
  }

  func load(profileID: String) -> TokenSet? { lock.withLock { stored[profileID] } }
  func save(_ tokens: TokenSet, profileID: String) { lock.withLock { stored[profileID] = tokens } }
  func delete(profileID: String) { lock.withLock { stored[profileID] = nil } }

  var isEmpty: Bool { lock.withLock { stored.isEmpty } }
}

enum TestSupport {

  /// 指向沒人監聽的 port——網路請求會立刻被拒絕，而不是等 DNS 逾時。
  /// 測試只從 doAction 注入結果，真正發出的請求本來就不該成功。
  static let baseURL = URL(string: "http://127.0.0.1:1/fhir")!

  static func makeClient() throws -> FHIRClient {
    try FHIRClient(baseURL: baseURL)
  }

  /// 建一個已登入的 TokenStore。不碰網路——測試只從 doAction 注入結果。
  static func makeTokenStore(
    fhirUser: String? = "Practitioner/137594487",
    storage: InMemoryTokenStorage = .init()
  ) throws -> TokenStore {
    let configuration = try JSONDecoder().decode(SmartConfiguration.self, from: Data("""
    {
      "authorization_endpoint": "https://example.org/auth/authorize",
      "token_endpoint": "https://example.org/auth/token",
      "code_challenge_methods_supported": ["S256"],
      "capabilities": ["launch-standalone", "client-public"]
    }
    """.utf8))

    // 必須先存再建：TokenStore 的 init 會從 storage 載入既有 session
    // （app 重啟後恢復登入狀態靠的就是這條路徑）。
    storage.save(
      TokenSet(
        accessToken: "token",
        refreshToken: nil,
        expiresAt: Date(timeIntervalSinceNow: 3600),
        grantedScopes: [],
        fhirUser: fhirUser,
        patient: nil
      ),
      profileID: "test"
    )

    return TokenStore(
      client: SmartAuthClient(),
      configuration: configuration,
      clientID: "tideng",
      profileID: "test",
      storage: storage
    )
  }

  static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }

  static func bundle(_ json: String) throws -> FHIR.Bundle {
    try decode(FHIR.Bundle.self, json)
  }
}

/// 記錄 ViewModel 發出的導航意圖。
///
/// `onRoute` 是 escaping closure，直接捕獲 local var 在 Swift 6 的隔離檢查下會卡；
/// 用一個 @MainActor 的小容器收集比較乾淨。
@MainActor
final class RouteRecorder<Route> {

  private(set) var routes: [Route] = []

  var last: Route? { routes.last }

  func record(_ route: Route) {
    routes.append(route)
  }
}

extension TestSupport {

  /// 把 bundle 包成解碼結果。`skipped` 大於 0 時代表回應不完整，
  /// 計數應降級為下限值。
  static func response(_ bundle: FHIR.Bundle, skipped: Int = 0) -> FHIRBundleDecoder.Result {
    .init(bundle: bundle, skippedEntries: skipped, decodedEntries: bundle.entry?.count ?? 0)
  }
}
