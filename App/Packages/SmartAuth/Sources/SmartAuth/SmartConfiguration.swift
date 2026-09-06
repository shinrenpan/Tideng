import Foundation

/// `{base}/.well-known/smart-configuration` 的回應。
///
/// 只宣告 MVP 真正會用到的欄位——多解一個欄位就多一個 server 可能不給、害整個 discovery
/// 解不出來的風險。
public struct SmartConfiguration: Decodable, Sendable, Equatable {

    public let issuer: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    /// 驗 `id_token` 簽章要用的公鑰位址。
    ///
    /// SMART 規格上是選填，所以是 optional——沒有它就驗不了簽，那時的正確行為是
    /// 「這個身分不可信、不使用」，而不是把使用者擋在門外。
    public let jwksURI: URL?
    public let capabilities: [String]
    public let codeChallengeMethodsSupported: [String]
    public let scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case jwksURI = "jwks_uri"
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case capabilities
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
    }
}

public extension SmartConfiguration {

    /// 這個 server 支不支援我們要走的流程。
    ///
    /// 在發起授權**之前**就擋下來，比讓使用者填完帳密才失敗好——而且錯誤訊息能講清楚
    /// 是 server 不支援，不是使用者做錯。
    func validateForStandaloneLaunch() throws {
        guard capabilities.contains("launch-standalone") else {
            throw SmartAuthError.unsupportedServer(reason: "此伺服器不支援 standalone 登入（capabilities 缺少 launch-standalone）")
        }
        guard capabilities.contains("client-public") else {
            throw SmartAuthError.unsupportedServer(reason: "此伺服器不接受 public client（capabilities 缺少 client-public）")
        }
        guard codeChallengeMethodsSupported.contains("S256") else {
            throw SmartAuthError.unsupportedServer(reason: "此伺服器不支援 PKCE（code_challenge_methods_supported 缺少 S256）")
        }
    }

    /// server 實際支援的 scope 才送出去。
    ///
    /// 送出 server 不認得的 scope，有些實作會整個拒絕授權請求而不是忽略它。
    /// `scopes_supported` 沒給時（規格上是選填）就照原樣送，讓 server 自己裁決。
    func negotiatedScopes(from requested: [String]) -> [String] {
        guard let supported = scopesSupported, !supported.isEmpty else { return requested }
        return requested.filter(supported.contains)
    }
}
