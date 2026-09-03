import Foundation

/// 一次登入拿到的全部憑證與 context。
public struct TokenSet: Codable, Sendable, Equatable {

    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    /// server **實際授予**的 scope，UI 依此決定顯示哪些功能。
    public let grantedScopes: [String]
    /// 形如 `Practitioner/123`，所有寫入的 performer 來源。
    public let fhirUser: String?
    public let patient: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        grantedScopes: [String],
        fhirUser: String?,
        patient: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.grantedScopes = grantedScopes
        self.fhirUser = fhirUser
        self.patient = patient
    }

    public init(response: TokenResponse, now: Date = .now) {
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        self.expiresAt = response.expiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
        self.grantedScopes = response.grantedScopes
        self.fhirUser = response.idToken.flatMap { IDTokenClaims(unverifiedIDToken: $0)?.fhirUser }
        self.patient = response.patient
    }

    /// 提前 60 秒視為過期。
    ///
    /// 拿一個「還有 3 秒到期」的 token 去發請求，等它走完網路就已經失效了——
    /// 換來的是一次註定失敗的 401 和一輪多餘的重試。
    public func isExpired(asOf now: Date = .now, leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }   // server 沒給 expires_in 就交給 401 處理
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// TokenSet 的持久化。
///
/// 抽成 protocol 是為了讓 `TokenStore` 的併發測試不必碰 Keychain——
/// 測試環境沒有 entitlement，而要測的是序列化邏輯不是儲存。
public protocol TokenPersisting: Sendable {
    func load(profileID: String) -> TokenSet?
    func save(_ tokens: TokenSet, profileID: String)
    func delete(profileID: String)
}
