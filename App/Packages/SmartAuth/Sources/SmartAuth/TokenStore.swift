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

    private var tokens: TokenSet?
    /// 進行中的 refresh。多個請求同時撞到過期時共享同一個 task，只打一次 token endpoint。
    private var refreshTask: Task<TokenSet, any Error>?

    public init(
        client: SmartAuthClient,
        configuration: SmartConfiguration,
        clientID: String,
        profileID: String,
        storage: any TokenPersisting
    ) {
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

    public func adopt(_ response: TokenResponse) {
        let set = TokenSet(response: response)
        tokens = set
        storage.save(set, profileID: profileID)
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

        let task = Task<TokenSet, any Error> { [client, configuration, clientID] in
            let response = try await client.refresh(
                refreshToken: refreshToken,
                configuration: configuration,
                clientID: clientID
            )
            return TokenSet(response: response)
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
