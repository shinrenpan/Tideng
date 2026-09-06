import Foundation
import Security

/// 驗證 `id_token` 的簽章與 issuer，然後才取出裡面的 claim。
///
/// 為什麼需要它：`fhirUser` 決定畫面上顯示的身分，也是之後所有寫入的 performer
/// 來源。沒有驗簽的話，任何人都能給出一個宣稱自己是某位醫事人員的 token。
///
/// 驗不過時**不結束 session**：真正的授權判斷在 FHIR server 對 access token 做，
/// 這裡管的只是「這個身分可不可信」。把顯示問題升級成登出，是把小事變大事。
public actor IDTokenVerifier {

    private let jwksURI: URL?
    private let expectedIssuer: String?
    private let session: URLSession

    /// kid → 公鑰。抓過一次就留著——每次驗證都去抓，等於把 IdP 放進熱路徑。
    private var keys: [String: SecKey]?

    public init(configuration: SmartConfiguration, session: URLSession = .shared) {
        self.jwksURI = configuration.jwksURI
        self.expectedIssuer = configuration.issuer
        self.session = session
    }

    /// 驗過的 claims。任何一步不成立都回 `nil`——呼叫端據此讓身分留白。
    ///
    /// 不區分失敗原因，因為使用者對此無可作為：簽章錯、issuer 不符、抓不到金鑰，
    /// 三者的結果都是「這個身分不能用」。
    public func verifiedClaims(of idToken: String) async -> IDTokenClaims? {
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let header = Self.decodeJSON(String(segments[0])),
              let signature = Self.base64URLDecode(String(segments[2]))
        else { return nil }

        // 只接受 RS256。**這是縱深防禦，不是唯一的關卡**——實測拿掉它之後
        // `alg=none` 仍會被拒，因為空簽章過不了下面的 RSA 驗證。留著是為了讓
        // 意圖寫在程式碼裡，也為了日後有人重構驗證路徑時不會靜默放行。
        guard header["alg"] as? String == "RS256" else { return nil }
        guard let key = await key(withID: header["kid"] as? String) else { return nil }

        let signedInput = Data("\(segments[0]).\(segments[1])".utf8)
        guard SecKeyVerifySignature(
            key, .rsaSignatureMessagePKCS1v15SHA256,
            signedInput as CFData, signature as CFData, nil
        ) else { return nil }

        // 簽章對了還要問「是誰簽的」——一把有效的金鑰若來自別的 issuer，
        // 它證明的是別人家的使用者，不是我們這台 server 的。
        guard let claims = IDTokenClaims(unverifiedIDToken: idToken) else { return nil }
        if let expectedIssuer, claims.issuer != expectedIssuer { return nil }
        return claims
    }

    // MARK: - 金鑰

    private func key(withID kid: String?) async -> SecKey? {
        if keys == nil { keys = await fetchKeys() }
        guard let keys, !keys.isEmpty else { return nil }
        if let kid { return keys[kid] }
        // 沒帶 kid 且只有一把時就用那把——單一金鑰的 server 常常不帶 kid。
        return keys.count == 1 ? keys.values.first : nil
    }

    private func fetchKeys() async -> [String: SecKey] {
        // FHIR server 發布的 jwks_uri 只是提示，它可能填錯——實測 Siming 會把自己
        // 容器內用的位址發出來，那個位址 client 根本連不到。
        //
        // 真正的權威來源是 issuer 自己的 OIDC discovery：驗 id_token 的金鑰屬於
        // 簽發它的人。所以提示不通時就回頭問 issuer。
        //
        // ⚠️ issuer 取自**設定**（使用者輸入的 FHIR server 所發布的），不是 token
        // 自己宣稱的 `iss`——否則偽造者只要指定自己的 issuer 就能自帶金鑰。
        // 依序嘗試，不要寫成陣列字面值——那會**先**求值第二個候選，
        // 於是「提示優先、失敗才問 issuer」變成兩個都問、順序還相反。
        if let jwksURI {
            let keys = await fetchKeys(from: jwksURI)
            if !keys.isEmpty { return keys }
        }
        if let fallback = await issuerJWKSURL() {
            return await fetchKeys(from: fallback)
        }
        return [:]
    }

    /// 從 `{issuer}/.well-known/openid-configuration` 問出 jwks_uri。
    private func issuerJWKSURL() async -> URL? {
        guard let expectedIssuer, var url = URL(string: expectedIssuer) else { return nil }
        url.append(path: ".well-known/openid-configuration")
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jwks = root["jwks_uri"] as? String
        else { return nil }
        return URL(string: jwks)
    }

    private func fetchKeys(from url: URL) async -> [String: SecKey] {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jwks = root["keys"] as? [[String: Any]]
        else { return [:] }

        var result: [String: SecKey] = [:]
        for jwk in jwks {
            guard jwk["kty"] as? String == "RSA",
                  let kid = jwk["kid"] as? String,
                  let n = (jwk["n"] as? String).flatMap(Self.base64URLDecode),
                  let e = (jwk["e"] as? String).flatMap(Self.base64URLDecode),
                  let key = Self.makeRSAKey(modulus: n, exponent: e)
            else { continue }
            result[kid] = key
        }
        return result
    }

    /// 從 modulus 與 exponent 組出 PKCS#1 的 `SEQUENCE { INTEGER n, INTEGER e }`。
    private static func makeRSAKey(modulus: Data, exponent: Data) -> SecKey? {
        let der = derSequence([derInteger(modulus), derInteger(exponent)])
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        return SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil)
    }

    private static func derInteger(_ value: Data) -> Data {
        // 最高位元是 1 的話，DER 的 INTEGER 會被讀成負數——前面補一個 0x00。
        var content = value
        if let first = content.first, first & 0x80 != 0 { content.insert(0x00, at: content.startIndex) }
        return Data([0x02]) + derLength(content.count) + content
    }

    private static func derSequence(_ elements: [Data]) -> Data {
        let content = elements.reduce(Data(), +)
        return Data([0x30]) + derLength(content.count) + content
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 { bytes.insert(UInt8(remaining & 0xFF), at: 0); remaining >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    // MARK: -

    private static func decodeJSON(_ segment: String) -> [String: Any]? {
        guard let data = base64URLDecode(segment) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
