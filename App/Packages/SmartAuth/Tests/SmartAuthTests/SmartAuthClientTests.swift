import Foundation
import Testing
@testable import SmartAuth

extension StubBackedTests {

  @Suite
  struct SmartAuthClientTests {

    private let base = URL(string: "http://localhost:8090/v/r4/fhir")!

    private func makeClient() -> SmartAuthClient {
        SmartAuthClient(session: StubURLProtocol.makeSession())
    }

    private func makeConfiguration() throws -> SmartConfiguration {
        try JSONDecoder().decode(SmartConfiguration.self, from: Fixtures.smartConfiguration)
    }

    // MARK: - Discovery

    @Test("discovery 打對路徑並解出端點")
    func fetchesConfiguration() async throws {
        StubURLProtocol.stub(body: Fixtures.smartConfiguration)

        let configuration = try await makeClient().discover(baseURL: base)

        let requestedURL = try #require(StubURLProtocol.lastRequest?.url?.absoluteString)
        #expect(requestedURL == "http://localhost:8090/v/r4/fhir/.well-known/smart-configuration")
        #expect(configuration.authorizationEndpoint.absoluteString == "http://localhost:8090/v/r4/auth/authorize")
        #expect(configuration.tokenEndpoint.absoluteString == "http://localhost:8090/v/r4/auth/token")
    }

    @Test("沒有 well-known 時給明確錯誤，不安靜降級")
    func reportsMissingDiscovery() async throws {
        StubURLProtocol.stub(status: 404)

        await #expect(throws: SmartAuthError.self) {
            _ = try await makeClient().discover(baseURL: base)
        }
    }

    @Test("standalone launch 的能力檢查")
    func validatesCapabilities() throws {
        let supported = try makeConfiguration()
        #expect(throws: Never.self) { try supported.validateForStandaloneLaunch() }

        let legacy = try JSONDecoder().decode(SmartConfiguration.self, from: Fixtures.configurationWithoutPKCE)
        #expect(throws: SmartAuthError.self) { try legacy.validateForStandaloneLaunch() }
    }

    // MARK: - 五種缺漏都必須在開瀏覽器之前擋下來

    @Test(
      "缺少流程必需的欄位時，訊息指出缺了哪一個",
      arguments: [
        (Fixtures.configurationWithoutAuthorizeEndpoint, "authorization_endpoint"),
        (Fixtures.configurationWithoutTokenEndpoint, "token_endpoint"),
        (Fixtures.configurationWithoutChallengeMethods, "code_challenge_methods_supported")
      ]
    )
    func namesTheMissingField(document: Data, field: String) async throws {
        StubURLProtocol.stub(body: document)

        let error = await #expect(throws: SmartAuthError.self) {
            _ = try await makeClient().discover(baseURL: base)
        }

        // 「設定格式無法解讀」對使用者與之後除錯的人都沒有用——訊息要說是哪個欄位，
        // 才分得出「server 不支援」與「我打錯網址」。
        let reason = try #require(error?.serverDiagnostics)
        #expect(reason.contains(field), "訊息沒有指出 \(field)：\(reason)")
    }

    @Test(
      "缺少必要能力時在授權前擋下，且分得出缺的是哪一項",
      arguments: [
        (Fixtures.configurationWithoutStandaloneLaunch, "launch-standalone"),
        (Fixtures.configurationWithoutPublicClient, "client-public")
      ]
    )
    func namesTheMissingCapability(document: Data, capability: String) throws {
        let configuration = try JSONDecoder().decode(SmartConfiguration.self, from: document)

        let error = #expect(throws: SmartAuthError.self) {
            try configuration.validateForStandaloneLaunch()
        }

        let reason = try #require(error?.serverDiagnostics)
        #expect(reason.contains(capability), "訊息沒有指出 \(capability)：\(reason)")
    }

    // MARK: - Token 交換

    @Test("換 token 送出 PKCE verifier 與正確的 grant_type")
    func exchangesCode() async throws {
        StubURLProtocol.stub(body: Fixtures.tokenResponse)
        let request = AuthorizationRequest(
            configuration: try makeConfiguration(),
            clientID: "tideng",
            redirectURI: URL(string: "tideng://smart/callback")!,
            fhirBaseURL: base,
            scopes: ["openid", "fhirUser", "offline_access"]
        )

        let token = try await makeClient().exchangeCode("the-code", for: request)

        let sent = try #require(StubURLProtocol.lastRequest)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        let body = try #require(StubURLProtocol.lastBody.map { String(decoding: $0, as: UTF8.self) })
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=the-code"))
        #expect(body.contains("code_verifier=\(request.pkce.verifier)"))
        // public client：不得出現 client_secret
        #expect(!body.contains("client_secret"))

        #expect(token.accessToken == "eyJhbGciOiJIUzI1NiJ9.access")
        #expect(token.refreshToken == "refresh-abc-123")
        #expect(token.grantedScopes.contains("offline_access"))
    }

    @Test("refresh 用 refresh_token grant")
    func refreshesToken() async throws {
        StubURLProtocol.stub(body: Fixtures.tokenResponse)

        _ = try await makeClient().refresh(
            refreshToken: "refresh-abc-123",
            configuration: try makeConfiguration(),
            clientID: "tideng"
        )

        let body = try #require(StubURLProtocol.lastBody.map { String(decoding: $0, as: UTF8.self) })
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=refresh-abc-123"))
    }

    @Test("server 的 error_description 傳達給使用者")
    func surfacesOAuthError() async throws {
        StubURLProtocol.stub(status: 400, body: Fixtures.invalidGrant)

        do {
            _ = try await makeClient().refresh(
                refreshToken: "expired",
                configuration: try makeConfiguration(),
                clientID: "tideng"
            )
            Issue.record("預期要拋錯")
        } catch let error as SmartAuthError {
            #expect(error == .tokenExchangeFailed(reason: "授權碼已過期或已使用"))
        }
    }

    // MARK: - 編碼

    @Test("form 編碼把 + 編成 %2B")
    func encodesPlusSign() {
        // 在 form-urlencoded 裡 `+` 代表空格。authorization code 含 `+` 而沒編碼時，
        // 送出去的值是錯的，而 server 只會回一句沒頭沒尾的 invalid_grant。
        let encoded = SmartAuthClient.formURLEncoded(["code": "a+b/c=d"])
        #expect(String(decoding: encoded, as: UTF8.self) == "code=a%2Bb%2Fc%3Dd")
    }

    // MARK: - id_token

    @Test("從 id_token 解出 fhirUser")
    func parsesFHIRUser() throws {
        StubURLProtocol.stub(body: Fixtures.tokenResponse)
        let token = try JSONDecoder().decode(TokenResponse.self, from: Fixtures.tokenResponse)
        let idToken = try #require(token.idToken)
        let claims = try #require(IDTokenClaims(unverifiedIDToken: idToken))

        #expect(claims.fhirUser == "Practitioner/123")
        #expect(claims.subject == "practitioner-1")
    }

    @Test("格式不對的 id_token 回 nil 而不是崩潰")
    func rejectsMalformedIDToken() {
        #expect(IDTokenClaims(unverifiedIDToken: "not-a-jwt") == nil)
        #expect(IDTokenClaims(unverifiedIDToken: "a.b") == nil)
        #expect(IDTokenClaims(unverifiedIDToken: "") == nil)
    }
}
}
