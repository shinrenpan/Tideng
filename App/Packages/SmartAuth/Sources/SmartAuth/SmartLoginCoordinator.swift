import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

/// 走完一次 standalone launch：discovery → 瀏覽器授權 → 換 token。
///
/// 這是 SmartAuth 唯一碰 UI 的地方，其餘全是可離線測試的純協定邏輯。
@MainActor
public final class SmartLoginCoordinator: NSObject {

    private let client: SmartAuthClient
    private let storage: any TokenPersisting
    private weak var anchor: ASPresentationAnchor?

    /// 授權中的 session。留著才能在使用者取消時正確收尾。
    private var webSession: ASWebAuthenticationSession?

    public init(
        client: SmartAuthClient = SmartAuthClient(),
        storage: any TokenPersisting = KeychainTokenStorage()
    ) {
        self.client = client
        self.storage = storage
    }

    /// - Parameters:
    ///   - profileID: server profile 的 id，決定憑證存在 Keychain 的哪一格。
    ///   - anchor: 呈現授權瀏覽器的視窗。給 `nil` 時自己找目前的 key window——
    ///     這樣 ViewModel 發起登入時完全不必碰 UI 型別。
    public func signIn(
        fhirBaseURL: URL,
        clientID: String,
        redirectURI: URL,
        scopes: [String],
        profileID: String,
        from anchor: ASPresentationAnchor? = nil
    ) async throws -> TokenStore {
        self.anchor = anchor ?? Self.currentKeyWindow()

        let configuration = try await client.discover(baseURL: fhirBaseURL)
        try configuration.validateForStandaloneLaunch()

        let request = AuthorizationRequest(
            configuration: configuration,
            clientID: clientID,
            redirectURI: redirectURI,
            fhirBaseURL: fhirBaseURL,
            scopes: scopes
        )

        let callback = try await presentAuthorization(
            url: try request.makeAuthorizationURL(),
            callbackScheme: redirectURI.scheme
        )
        let code = try request.authorizationCode(from: callback)
        let response = try await client.exchangeCode(code, for: request)

        let store = TokenStore(
            client: client,
            configuration: configuration,
            clientID: clientID,
            profileID: profileID,
            storage: storage
        )
        await store.adopt(response)
        return store
    }

    private func presentAuthorization(url: URL, callbackScheme: String?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    continuation.resume(
                        throwing: code == .canceledLogin
                            ? SmartAuthError.userCancelled
                            : SmartAuthError.transport(message: error.localizedDescription)
                    )
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: SmartAuthError.tokenExchangeFailed(reason: "授權沒有回傳結果"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = self
            // 共用 iPad 不留 SSO cookie，每次都是乾淨登入。
            // 代價是記不住帳號——在多人輪流用同一台的場景下，這是特性不是缺點。
            session.prefersEphemeralWebBrowserSession = true

            webSession = session
            guard session.start() else {
                continuation.resume(throwing: SmartAuthError.transport(message: "無法開啟授權頁面"))
                return
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SmartLoginCoordinator: ASWebAuthenticationPresentationContextProviding {

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? Self.currentKeyWindow() ?? ASPresentationAnchor()
    }
}

private extension SmartLoginCoordinator {

    static func currentKeyWindow() -> ASPresentationAnchor? {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        #else
        nil
        #endif
    }
}
