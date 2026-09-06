import Foundation

/// token endpoint 的回應（SMART App Launch 在 OAuth 2 之上多加了幾個欄位）。
public struct TokenResponse: Decodable, Sendable, Equatable {

    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let idToken: String?
    /// server **實際授予**的 scope。可能少於請求的，UI 要依此隱藏無權限的功能。
    public let scope: String?
    /// standalone patient launch 時 server 選定的病人。
    public let patient: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case scope
        case patient
    }

    public var grantedScopes: [String] {
        scope?.split(separator: " ").map(String.init) ?? []
    }
}

/// `id_token` 裡我們需要的 claim。
public struct IDTokenClaims: Sendable, Equatable {

    /// 形如 `Practitioner/123`——所有寫入的 performer 都來自這裡。
    public let fhirUser: String?
    public let subject: String?
    /// 簽發者。驗簽通過還要比對它——一把有效的金鑰若來自別的 issuer，
    /// 證明的是別人家的使用者。
    public let issuer: String?

    /// 只解 payload，**不驗簽章**。
    ///
    /// MVP 階段的 id_token 來自模擬器，本來就不可信；正式驗簽（走 jwks_uri）列為 Phase B。
    /// 在那之前，這裡解出來的身分只能拿來顯示與組 reference，不能當作授權依據——
    /// 真正的授權判斷在 server 端對 access token 做。
    public init?(unverifiedIDToken token: String) {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        guard let data = Self.base64URLDecode(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        self.fhirUser = json["fhirUser"] as? String
        self.subject = json["sub"] as? String
        self.issuer = json["iss"] as? String
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // base64url 去掉了 padding，解碼前要補回來。
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
