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
}
