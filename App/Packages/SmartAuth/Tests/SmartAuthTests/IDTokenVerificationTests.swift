import Foundation
import Security
import Testing
@testable import SmartAuth

extension StubBackedTests {

  /// `fhirUser` 決定畫面上的身分，也是之後所有寫入的 performer 來源。
  /// 沒有驗簽，任何人都能宣稱自己是某位醫事人員。
  @Suite
  struct IDTokenVerificationTests {

    private let issuer = "http://localhost:8081/realms/tideng"

    // MARK: - 通過

    @Test("簽章與 issuer 都對時取得 fhirUser")
    func acceptsGenuineToken() async throws {
      let signer = try JWTSigner()
      StubURLProtocol.stub(body: signer.jwksJSON)
      let verifier = makeVerifier()

      let token = try signer.sign(claims: [
        "iss": issuer, "sub": "chiu", "fhirUser": "Practitioner/practitioner-3"
      ])
      let claims = await verifier.verifiedClaims(of: token)

      #expect(claims?.fhirUser == "Practitioner/practitioner-3")
    }

    // MARK: - 不通過（三種都不產生身分）

    @Test("簽章對不上時不產生身分")
    func rejectsForgedSignature() async throws {
      let genuine = try JWTSigner()
      let attacker = try JWTSigner()
      // server 公布的是真金鑰，token 卻是攻擊者簽的
      StubURLProtocol.stub(body: genuine.jwksJSON)
      let verifier = makeVerifier()

      let forged = try attacker.sign(
        claims: ["iss": issuer, "fhirUser": "Practitioner/practitioner-3"],
        kid: genuine.kid   // 連 kid 都抄對
      )

      #expect(await verifier.verifiedClaims(of: forged) == nil)
    }

    @Test("issuer 不符時不產生身分")
    func rejectsWrongIssuer() async throws {
      let signer = try JWTSigner()
      StubURLProtocol.stub(body: signer.jwksJSON)
      let verifier = makeVerifier()

      let token = try signer.sign(claims: [
        "iss": "https://evil.example.org/realms/tideng",
        "fhirUser": "Practitioner/practitioner-3"
      ])

      #expect(await verifier.verifiedClaims(of: token) == nil)
    }

    @Test("jwks 抓不到時不產生身分")
    func rejectsWhenKeysUnavailable() async throws {
      let signer = try JWTSigner()
      StubURLProtocol.stub(status: 500)
      let verifier = makeVerifier()

      let token = try signer.sign(claims: ["iss": issuer, "fhirUser": "Practitioner/x"])

      #expect(await verifier.verifiedClaims(of: token) == nil)
    }

    @Test("alg=none 不產生身分")
    func rejectsUnsignedToken() async throws {
      // 最經典的 JWT 攻擊：把 alg 改成 none、簽章留空。
      let signer = try JWTSigner()
      StubURLProtocol.stub(body: signer.jwksJSON)

      func b64(_ object: [String: Any]) -> String {
        try! JSONSerialization.data(withJSONObject: object).base64EncodedString()
          .replacingOccurrences(of: "+", with: "-")
          .replacingOccurrences(of: "/", with: "_")
          .replacingOccurrences(of: "=", with: "")
      }
      let unsigned = b64(["alg": "none", "typ": "JWT"]) + "."
        + b64(["iss": issuer, "fhirUser": "Practitioner/practitioner-3"]) + "."

      #expect(await makeVerifier().verifiedClaims(of: unsigned) == nil)
    }

    @Test("格式不是 JWT 時不產生身分")
    func rejectsMalformedToken() async throws {
      let signer = try JWTSigner()
      StubURLProtocol.stub(body: signer.jwksJSON)

      #expect(await makeVerifier().verifiedClaims(of: "not.a.jwt") == nil)
    }

    @Test("發布的 jwks_uri 連不到時，回頭問 issuer")
    func fallsBackToIssuerDiscovery() async throws {
      let signer = try JWTSigner()
      // 第一次請求（server 發布的 jwks_uri）失敗；
      // 第二次是 issuer 的 openid-configuration；第三次才是真的 jwks。
      StubURLProtocol.stubSequence([
        (500, Data()),
        (200, Data(#"{"jwks_uri":"https://issuer.example.org/certs"}"#.utf8)),
        (200, signer.jwksJSON),
      ])
      let verifier = makeVerifier()

      let token = try signer.sign(claims: [
        "iss": issuer, "fhirUser": "Practitioner/practitioner-3"
      ])

      #expect(await verifier.verifiedClaims(of: token)?.fhirUser == "Practitioner/practitioner-3")
    }

    // MARK: - 快取

    @Test("公鑰取得後重複驗證不再重新請求")
    func cachesKeys() async throws {
      let signer = try JWTSigner()
      StubURLProtocol.stub(body: signer.jwksJSON)
      let verifier = makeVerifier()
      let token = try signer.sign(claims: ["iss": issuer, "fhirUser": "Practitioner/x"])

      _ = await verifier.verifiedClaims(of: token)
      let afterFirst = StubURLProtocol.requestCount
      _ = await verifier.verifiedClaims(of: token)

      #expect(StubURLProtocol.requestCount == afterFirst, "第二次驗證又去抓了一次 jwks")
    }

    // MARK: -

    private func makeVerifier() -> IDTokenVerifier {
      let configuration = SmartConfiguration(
        issuer: issuer,
        authorizationEndpoint: URL(string: "https://example.org/auth")!,
        tokenEndpoint: URL(string: "https://example.org/token")!,
        jwksURI: URL(string: "https://example.org/certs")!,
        capabilities: ["launch-standalone", "client-public"],
        codeChallengeMethodsSupported: ["S256"],
        scopesSupported: nil
      )
      return IDTokenVerifier(configuration: configuration, session: StubURLProtocol.makeSession())
    }
  }
}
