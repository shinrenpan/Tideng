import Foundation

enum Fixtures {

    /// 真的從本機 smart-launcher-v2 抓下來的回應（`GET /v/r4/fhir/.well-known/smart-configuration`）。
    /// 用真實回應當 fixture，才測得到真實 server 會給的欄位組合。
    static let smartConfiguration = Data("""
    {
      "issuer": "http://localhost:8090/v/r4/fhir",
      "jwks_uri": "http://localhost:8090/keys",
      "authorization_endpoint": "http://localhost:8090/v/r4/auth/authorize",
      "grant_types_supported": ["authorization_code", "client_credentials"],
      "token_endpoint": "http://localhost:8090/v/r4/auth/token",
      "code_challenge_methods_supported": ["S256"],
      "scopes_supported": [
        "openid", "profile", "fhirUser", "launch", "launch/patient",
        "launch/encounter", "patient/*.*", "user/*.*", "offline_access"
      ],
      "response_types_supported": ["code", "token", "id_token", "token id_token", "refresh_token"],
      "capabilities": [
        "launch-ehr", "launch-standalone", "client-public", "client-confidential-symmetric",
        "sso-openid-connect", "context-passthrough-banner", "context-passthrough-style",
        "context-ehr-patient", "context-ehr-encounter", "context-standalone-patient",
        "context-standalone-encounter", "permission-offline", "permission-patient",
        "permission-user", "permission-v1", "permission-v2", "authorize-post", "introspection"
      ]
    }
    """.utf8)

    /// 不支援 PKCE 的舊 server。
    static let configurationWithoutPKCE = Data("""
    {
      "authorization_endpoint": "https://legacy.example.org/auth",
      "token_endpoint": "https://legacy.example.org/token",
      "code_challenge_methods_supported": ["plain"],
      "capabilities": ["launch-standalone", "client-public"]
    }
    """.utf8)

    static let tokenResponse = Data("""
    {
      "access_token": "eyJhbGciOiJIUzI1NiJ9.access",
      "token_type": "Bearer",
      "expires_in": 300,
      "refresh_token": "refresh-abc-123",
      "scope": "openid fhirUser user/*.read offline_access",
      "id_token": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcmFjdGl0aW9uZXItMSIsImZoaXJVc2VyIjoiUHJhY3RpdGlvbmVyLzEyMyJ9.sig"
    }
    """.utf8)

    /// OAuth 2 的錯誤回應（RFC 6749 §5.2）。
    static let invalidGrant = Data("""
    { "error": "invalid_grant", "error_description": "授權碼已過期或已使用" }
    """.utf8)

    // MARK: - 缺漏的 discovery 文件
    //
    // 五種缺漏各一份。缺前三個欄位時 client 連解都解不出來，缺後兩項能力時
    // 解得出來但不該進入授權——兩類的訊息必須分得出來，否則使用者（和之後
    // 除錯的人）只會看到「連不上」。

    /// 缺 `authorization_endpoint`：不知道要把使用者送去哪裡。
    static let configurationWithoutAuthorizeEndpoint = Data("""
    {
      "token_endpoint": "https://example.org/token",
      "code_challenge_methods_supported": ["S256"],
      "capabilities": ["launch-standalone", "client-public"]
    }
    """.utf8)

    /// 缺 `token_endpoint`：換得到 code 卻換不到 token。
    static let configurationWithoutTokenEndpoint = Data("""
    {
      "authorization_endpoint": "https://example.org/auth",
      "code_challenge_methods_supported": ["S256"],
      "capabilities": ["launch-standalone", "client-public"]
    }
    """.utf8)

    /// 缺 `code_challenge_methods_supported`：完全沒宣告 PKCE 支援。
    static let configurationWithoutChallengeMethods = Data("""
    {
      "authorization_endpoint": "https://example.org/auth",
      "token_endpoint": "https://example.org/token",
      "capabilities": ["launch-standalone", "client-public"]
    }
    """.utf8)

    /// 純 resource server：解得出來，但沒有 standalone launch。
    static let configurationWithoutStandaloneLaunch = Data("""
    {
      "authorization_endpoint": "https://example.org/auth",
      "token_endpoint": "https://example.org/token",
      "code_challenge_methods_supported": ["S256"],
      "capabilities": ["permission-v1", "client-public"]
    }
    """.utf8)

    /// 只接受 confidential client：public client 沒有 secret，走不了。
    static let configurationWithoutPublicClient = Data("""
    {
      "authorization_endpoint": "https://example.org/auth",
      "token_endpoint": "https://example.org/token",
      "code_challenge_methods_supported": ["S256"],
      "capabilities": ["launch-standalone", "client-confidential-symmetric"]
    }
    """.utf8)
}

