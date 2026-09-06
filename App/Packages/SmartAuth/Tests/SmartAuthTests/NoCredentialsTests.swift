import Foundation
import Testing
@testable import SmartAuth

/// app 永遠不接觸使用者的密碼——那是 SMART／OAuth 整套設計的目的。
///
/// 這不是「目前剛好沒有」，是一條不能被無聲打破的界線：一旦 app 持有密碼，
/// 診所就得信任我們不會亂用，而那正是「使用者自己輸入 FHIR URL」這個設計
/// 要避開的東西。
@Suite("app 不接觸密碼")
struct NoCredentialsTests {

    /// 持久化的欄位集合是白名單，不是黑名單。
    ///
    /// 黑名單（「沒有叫做 password 的欄位」）擋不住 `credential`、`secret`、
    /// `userPass` 這些名字；白名單則是新增任何欄位都會讓這條測試變紅，
    /// 逼人回來想一次「這個東西該不該被存下來」。
    ///
    /// 用 `Mirror` 看**宣告的欄位**而不是編碼後的 key：`Codable` 對 nil 的
    /// Optional 會整個省略，所以只看 JSON 的話，一個剛好是 nil 的密碼欄位
    /// 會完全隱形——那正是這條測試要擋的東西。
    @Test("存進 Keychain 的欄位只有 token 與 context")
    func persistedFieldsAreOnlyTokens() throws {
        let tokens = TokenSet(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1_788_000_000),
            grantedScopes: ["openid", "fhirUser"],
            fhirUser: "Practitioner/practitioner-1",
            patient: nil
        )

        let declared = Set(Mirror(reflecting: tokens).children.compactMap(\.label))
        let allowed: Set<String> = [
            "accessToken", "refreshToken", "expiresAt", "grantedScopes", "fhirUser", "patient"
        ]
        let unexpected = declared.subtracting(allowed)
        #expect(unexpected.isEmpty, "TokenSet 多了未預期的欄位：\(unexpected)")

        // 順帶確認上面那份白名單真的涵蓋了全部宣告，而不是比實際欄位還寬
        // ——寬鬆的白名單跟沒有白名單一樣。
        #expect(allowed.subtracting(declared).isEmpty, "白名單列了不存在的欄位，形同虛設")
    }

    /// 送給 authorization server 的參數裡不得有密碼。
    ///
    /// app 只送 code_verifier——它證明「換 token 的人就是發起授權的人」，
    /// 而不是「這個人知道密碼」。
    @Test("授權請求不含任何憑證欄位")
    func authorizationRequestCarriesNoCredentials() throws {
        let configuration = try JSONDecoder().decode(
            SmartConfiguration.self, from: Fixtures.smartConfiguration
        )
        let request = AuthorizationRequest(
            configuration: configuration,
            clientID: "tideng",
            redirectURI: URL(string: "tideng://smart/callback")!,
            fhirBaseURL: URL(string: "http://localhost:8080")!,
            scopes: ["openid", "fhirUser"]
        )

        let url = try request.makeAuthorizationURL()
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let names = Set((components.queryItems ?? []).map { $0.name })

        let forbidden: Set<String> = [
            "password", "passwd", "pwd", "secret", "client_secret", "credential", "username"
        ]
        #expect(names.isDisjoint(with: forbidden), "授權請求帶了憑證欄位：\(names.intersection(forbidden))")
    }
}
