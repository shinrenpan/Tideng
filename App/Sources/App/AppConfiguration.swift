import Foundation

/// 裝配期才決定的設定值。
enum AppConfiguration {

  /// 必須與 Info.plist 的 CFBundleURLSchemes 一致。
  static let redirectURI = URL(string: "tideng://smart/callback")!

  /// 要求的權限。
  ///
  /// server 實際授予的可能更少（見 TokenResponse.grantedScopes），UI 依實際授予決定顯示什麼。
  /// `offline_access` 是 refresh token 的前提——沒有它，閒置鎖定後就得重新登入。
  static let scopes = [
    "openid",
    "fhirUser",
    "user/*.read",
    "offline_access"
  ]
}
