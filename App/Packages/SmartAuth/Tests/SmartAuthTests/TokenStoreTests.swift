import Foundation
import Testing
@testable import SmartAuth

/// 測試用的儲存：要驗的是序列化邏輯，不是 Keychain
/// （SPM 測試環境沒有 entitlement，碰 Keychain 只會測到環境本身）。
final class InMemoryTokenStorage: TokenPersisting, @unchecked Sendable {

    private let lock = NSLock()
    private var stored: [String: TokenSet] = [:]

    init(seed: [String: TokenSet] = [:]) {
        self.stored = seed
    }

    func load(profileID: String) -> TokenSet? { lock.withLock { stored[profileID] } }
    func save(_ tokens: TokenSet, profileID: String) { lock.withLock { stored[profileID] = tokens } }
    func delete(profileID: String) { lock.withLock { stored[profileID] = nil } }

    var isEmpty: Bool { lock.withLock { stored.isEmpty } }
}

extension StubBackedTests {

  @Suite
  struct TokenStoreTests {

    private let profileID = "profile-1"

    private func makeConfiguration() throws -> SmartConfiguration {
        try JSONDecoder().decode(SmartConfiguration.self, from: Fixtures.smartConfiguration)
    }

    private func makeStore(seeded tokens: TokenSet?) throws -> (TokenStore, InMemoryTokenStorage) {
        let storage = InMemoryTokenStorage(seed: tokens.map { [profileID: $0] } ?? [:])
        let store = TokenStore(
            client: SmartAuthClient(session: StubURLProtocol.makeSession()),
            configuration: try makeConfiguration(),
            clientID: "tideng",
            profileID: profileID,
            storage: storage
        )
        return (store, storage)
    }

    private func expiredTokens(refreshToken: String? = "refresh-abc-123") -> TokenSet {
        TokenSet(
            accessToken: "stale-access",
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSinceNow: -10),
            grantedScopes: ["openid", "offline_access"],
            fhirUser: "Practitioner/123",
            patient: nil
        )
    }

    private func freshTokens() -> TokenSet {
        TokenSet(
            accessToken: "good-access",
            refreshToken: "refresh-abc-123",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            grantedScopes: ["openid"],
            fhirUser: "Practitioner/123",
            patient: nil
        )
    }

    // MARK: - 併發

    @Test("10 個並發請求撞到過期時，只打一次 token endpoint")
    func serialisesConcurrentRefresh() async throws {
        // 這是整個 SmartAuth 最容易寫出 race 的地方：沒有序列化的話，
        // 10 個請求會各自發一次 refresh，而每次 refresh 都會讓前一個 refresh token 失效。
        StubURLProtocol.stub(body: Fixtures.tokenResponse, delay: 0.1)
        let (store, _) = try makeStore(seeded: expiredTokens())

        let tokens = await withTaskGroup(of: String?.self, returning: [String?].self) { group in
            for _ in 0..<10 {
                group.addTask { try? await store.validToken() }
            }
            var results: [String?] = []
            for await value in group { results.append(value) }
            return results
        }

        #expect(StubURLProtocol.requestCount == 1)
        #expect(tokens.count == 10)
        #expect(tokens.allSatisfy { $0 == "eyJhbGciOiJIUzI1NiJ9.access" })
    }

    @Test("refresh 完成後，下一次請求不再重打")
    func reusesRefreshedToken() async throws {
        StubURLProtocol.stub(body: Fixtures.tokenResponse)
        let (store, _) = try makeStore(seeded: expiredTokens())

        _ = try await store.validToken()
        _ = try await store.validToken()

        #expect(StubURLProtocol.requestCount == 1)
    }

    // MARK: - 過期判斷

    @Test("token 還沒過期就不 refresh")
    func skipsRefreshWhenValid() async throws {
        StubURLProtocol.stub(body: Fixtures.tokenResponse)
        let (store, _) = try makeStore(seeded: freshTokens())

        let token = try await store.validToken()

        #expect(token == "good-access")
        #expect(StubURLProtocol.requestCount == 0)
    }

    @Test("快到期的 token 提前更新，不等它真的失效")
    func refreshesWithinLeeway() async throws {
        // 只剩 30 秒的 token 拿去發請求，等網路走完就已經失效了。
        let almostExpired = TokenSet(
            accessToken: "about-to-die",
            refreshToken: "refresh-abc-123",
            expiresAt: Date(timeIntervalSinceNow: 30),
            grantedScopes: [],
            fhirUser: nil,
            patient: nil
        )
        StubURLProtocol.stub(body: Fixtures.tokenResponse)
        let (store, _) = try makeStore(seeded: almostExpired)

        _ = try await store.validToken()

        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("server 沒給 expires_in 時不主動 refresh，交給 401 處理")
    func toleratesMissingExpiry() async throws {
        let noExpiry = TokenSet(
            accessToken: "no-expiry",
            refreshToken: "refresh-abc-123",
            expiresAt: nil,
            grantedScopes: [],
            fhirUser: nil,
            patient: nil
        )
        StubURLProtocol.stub(body: Fixtures.tokenResponse)
        let (store, _) = try makeStore(seeded: noExpiry)

        #expect(try await store.validToken() == "no-expiry")
        #expect(StubURLProtocol.requestCount == 0)
    }

    // MARK: - 失敗與登出

    @Test("refresh 失敗時清掉憑證並要求重新登入")
    func clearsSessionOnRefreshFailure() async throws {
        StubURLProtocol.stub(status: 400, body: Fixtures.invalidGrant)
        let (store, storage) = try makeStore(seeded: expiredTokens())

        await #expect(throws: SmartAuthError.sessionExpired) {
            _ = try await store.validToken()
        }
        #expect(storage.isEmpty)
        #expect(await store.isSignedIn == false)
    }

    @Test("沒有 refresh token（server 不給 offline_access）時直接要求重新登入")
    func requiresLoginWithoutRefreshToken() async throws {
        StubURLProtocol.stub(body: Fixtures.tokenResponse)
        let (store, _) = try makeStore(seeded: expiredTokens(refreshToken: nil))

        await #expect(throws: SmartAuthError.sessionExpired) {
            _ = try await store.validToken()
        }
        #expect(StubURLProtocol.requestCount == 0)
    }

    @Test("未登入時回 nil 而不是拋錯")
    func returnsNilWhenSignedOut() async throws {
        let (store, _) = try makeStore(seeded: nil)
        #expect(try await store.validToken() == nil)
    }

    @Test("登入後憑證寫進儲存，登出後清除")
    func persistsAndClears() async throws {
        let (store, storage) = try makeStore(seeded: nil)
        let response = try JSONDecoder().decode(TokenResponse.self, from: Fixtures.tokenResponse)

        await store.adopt(response)
        #expect(await store.isSignedIn)
        #expect(storage.load(profileID: profileID)?.accessToken == response.accessToken)

        await store.signOut()
        #expect(storage.isEmpty)
        #expect(await store.isSignedIn == false)
    }

    @Test("驗不過的 id_token 不產生身分，但 session 照常成立")
    func unverifiedIdentityDoesNotEndTheSession() async throws {
        // fixture 的 id_token 是假簽章，而測試環境沒有可用的 jwks——
        // 這正是「無法驗證」的情況。session 必須照常，只有身分留白。
        let (store, storage) = try makeStore(seeded: nil)
        let response = try JSONDecoder().decode(TokenResponse.self, from: Fixtures.tokenResponse)

        await store.adopt(response)

        #expect(await store.isSignedIn, "驗不過身分不該讓使用者被登出")
        #expect(try await store.validToken() == response.accessToken)
        #expect(storage.load(profileID: profileID)?.fhirUser == nil, "未驗證的身分不得被採用")
    }

    @Test("重新建立時從儲存回復 session")
    func restoresFromStorage() async throws {
        let (store, _) = try makeStore(seeded: freshTokens())
        #expect(await store.isSignedIn)
        #expect(await store.currentTokens?.fhirUser == "Practitioner/123")
    }
}
}
