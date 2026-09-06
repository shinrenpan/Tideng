import Foundation
import FHIRClient

/// 持有目前 session 的憑證，並在過期時自動更新。
///
/// 實作 `FHIRClient` 的 `TokenProviding`，所以 REST 層完全不需要認識 SMART。
public actor TokenStore: TokenProviding {

    private let client: SmartAuthClient
    private let configuration: SmartConfiguration
    private let clientID: String
    private let profileID: String
    private let storage: any TokenPersisting
    private let verifier: IDTokenVerifier

    private var tokens: TokenSet?
    /// 進行中的 refresh。多個請求同時撞到過期時共享同一個 task，只打一次 token endpoint。
    private var refreshTask: Task<TokenSet, any Error>?

    public init(
        client: SmartAuthClient,
        configuration: SmartConfiguration,
        clientID: String,
        profileID: String,
        storage: any TokenPersisting,
        verifier: IDTokenVerifier? = nil
    ) {
        self.verifier = verifier ?? IDTokenVerifier(configuration: configuration)
        self.client = client
        self.configuration = configuration
        self.clientID = clientID
        self.profileID = profileID
        self.storage = storage
        self.tokens = storage.load(profileID: profileID)
    }

    // MARK: - TokenProviding

    public func validToken() async throws -> String? {
        guard let tokens else { return nil }
        guard tokens.isExpired() else { return tokens.accessToken }
        return try await refresh().accessToken
    }

    // MARK: - Session 生命週期

    public func adopt(_ response: TokenResponse) async {
        let set = TokenSet(response: response, fhirUser: await verifiedFHIRUser(in: response))
        tokens = set
        storage.save(set, profileID: profileID)
    }

    /// 驗過簽章的 `fhirUser`；驗不過就是 nil。
    ///
    /// 驗不過**不會**讓登入失敗——授權由 FHIR server 對 access token 判斷，
    /// 這裡決定的只是「畫面上那個身分可不可信」。
    private func verifiedFHIRUser(in response: TokenResponse) async -> String? {
        guard let idToken = response.idToken else { return nil }
        return await verifier.verifiedClaims(of: idToken)?.fhirUser
    }

    public func signOut() {
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        storage.delete(profileID: profileID)
    }

    public var currentTokens: TokenSet? { tokens }
    public var isSignedIn: Bool { tokens != nil }

    /// 收到 401 時呼叫：強制更新一次。
    public func refreshAfterUnauthorized() async throws -> String {
        try await refresh().accessToken
    }

    // MARK: - 內部

    private func refresh() async throws -> TokenSet {
        // 已經有人在更新就等它——這裡到指派 refreshTask 之間沒有 await，
        // actor 保證這段是原子的，所以不會有兩個 task 同時被建立。
        if let refreshTask {
            return try await refreshTask.value
        }

        guard let refreshToken = tokens?.refreshToken else {
            // 沒有 refresh token（server 沒給 offline_access）就只能重新登入。
            throw SmartAuthError.sessionExpired
        }

        // 刷新前已驗過的身分。新回應沒帶 id_token 時沿用它——
        // 填 nil 會讓側邊欄在每次自動刷新後空掉，那是把安全措施做成 bug。
        let currentFHIRUser = tokens?.fhirUser

        let task = Task<TokenSet, any Error> { [client, configuration, clientID, verifier] in
            let response = try await client.refresh(
                refreshToken: refreshToken,
                configuration: configuration,
                clientID: clientID
            )
            // 帶了新的 id_token 就重驗一次；驗不過時不採用它，也不丟掉舊的——
            // 舊的那個是驗過的。
            var fhirUser = currentFHIRUser
            if let idToken = response.idToken,
               let verified = await verifier.verifiedClaims(of: idToken)?.fhirUser {
                fhirUser = verified
            }
            return TokenSet(response: response, fhirUser: fhirUser)
        }
        refreshTask = task

        do {
            let updated = try await task.value
            refreshTask = nil
            tokens = updated
            storage.save(updated, profileID: profileID)
            return updated
        } catch {
            refreshTask = nil
            // refresh 失敗代表這組憑證已經沒救，清掉並要求重新登入。
            // 注意：離線佇列不受影響，重登後繼續送。
            tokens = nil
            storage.delete(profileID: profileID)
            throw SmartAuthError.sessionExpired
        }
    }
}
