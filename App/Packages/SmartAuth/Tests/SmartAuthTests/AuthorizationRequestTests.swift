import Foundation
import Testing
@testable import SmartAuth

struct AuthorizationRequestTests {

    private func makeConfiguration() throws -> SmartConfiguration {
        try JSONDecoder().decode(SmartConfiguration.self, from: Fixtures.smartConfiguration)
    }

    private func makeRequest(
        scopes: [String] = ["openid", "fhirUser", "user/*.read", "offline_access"]
    ) throws -> AuthorizationRequest {
        AuthorizationRequest(
            configuration: try makeConfiguration(),
            clientID: "tideng",
            redirectURI: URL(string: "tideng://smart/callback")!,
            fhirBaseURL: URL(string: "http://localhost:8090/v/r4/fhir")!,
            scopes: scopes
        )
    }

    // MARK: - 授權網址

    @Test("授權網址帶齊 SMART 要求的參數")
    func buildsAuthorizationURL() throws {
        let request = try makeRequest()
        let url = try request.makeAuthorizationURL()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )

        #expect(components.path == "/v/r4/auth/authorize")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "tideng")
        #expect(query["redirect_uri"] == "tideng://smart/callback")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == request.pkce.challenge)
        #expect(query["state"] == request.state)
    }

    @Test("aud 必須存在且等於 FHIR base URL")
    func includesAudience() throws {
        // 這個參數最常被漏掉，漏掉時部分 server 會直接拒絕授權。
        let request = try makeRequest()
        let url = try request.makeAuthorizationURL()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let aud = components.queryItems?.first { $0.name == "aud" }?.value

        #expect(aud == "http://localhost:8090/v/r4/fhir")
    }

    @Test("只送出 server 宣告支援的 scope")
    func negotiatesScopes() throws {
        let request = try makeRequest(scopes: ["openid", "fhirUser", "offline_access", "user/Bogus.write"])
        #expect(request.scopes == ["openid", "fhirUser", "offline_access"])
    }

    @Test("每次請求的 state 都不同")
    func stateIsRandomPerRequest() throws {
        let states = try Set((0..<20).map { _ in try makeRequest().state })
        #expect(states.count == 20)
    }

    // MARK: - 回呼驗證

    @Test("正常回呼取得 authorization code")
    func extractsCode() throws {
        let request = try makeRequest()
        let callback = URL(string: "tideng://smart/callback?code=abc123&state=\(request.state)")!

        #expect(try request.authorizationCode(from: callback) == "abc123")
    }

    @Test("state 不符時拒絕，即使帶了 code")
    func rejectsMismatchedState() throws {
        let request = try makeRequest()
        let callback = URL(string: "tideng://smart/callback?code=abc123&state=attacker-supplied")!

        #expect(throws: SmartAuthError.stateMismatch) {
            try request.authorizationCode(from: callback)
        }
    }

    @Test("使用者取消時回報為取消，不是錯誤")
    func recognisesUserCancellation() throws {
        let request = try makeRequest()
        let callback = URL(string: "tideng://smart/callback?error=access_denied&error_description=User%20cancelled")!

        #expect(throws: SmartAuthError.userCancelled) {
            try request.authorizationCode(from: callback)
        }
    }

    @Test("server 回報的授權錯誤帶著說明往上拋")
    func surfacesAuthorizationError() throws {
        let request = try makeRequest()
        let callback = URL(string: "tideng://smart/callback?error=invalid_scope&error_description=Bad%20scope")!

        #expect(throws: SmartAuthError.authorizationDenied(error: "invalid_scope", description: "Bad scope")) {
            try request.authorizationCode(from: callback)
        }
    }
}
