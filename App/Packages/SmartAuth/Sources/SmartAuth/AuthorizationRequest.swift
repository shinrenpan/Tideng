import Foundation

/// 一次 standalone launch 的授權請求。
///
/// 建立時就決定 `state` 與 PKCE，回呼時用同一個實例驗證——兩者必須是同一次請求的，
/// 分開存會給錯配留下空間。
public struct AuthorizationRequest: Sendable {

    public let configuration: SmartConfiguration
    public let clientID: String
    public let redirectURI: URL
    /// 會成為 `aud` 參數。
    public let fhirBaseURL: URL
    public let scopes: [String]

    let pkce: PKCE
    let state: String

    public init(
        configuration: SmartConfiguration,
        clientID: String,
        redirectURI: URL,
        fhirBaseURL: URL,
        scopes: [String]
    ) {
        self.configuration = configuration
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.fhirBaseURL = fhirBaseURL
        self.scopes = configuration.negotiatedScopes(from: scopes)
        self.pkce = PKCE()
        self.state = Self.makeState()
    }

    public func makeAuthorizationURL() throws -> URL {
        guard var components = URLComponents(
            url: configuration.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw SmartAuthError.discoveryFailed(reason: "authorization_endpoint 不是合法的 URL")
        }

        // 保留 endpoint 自帶的 query（launcher 的 sim 參數就編在裡面）。
        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            // SMART 規格要求，而且是最常被漏掉的一個——漏掉時部分 server 直接拒絕授權。
            URLQueryItem(name: "aud", value: fhirBaseURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method)
        ])
        components.queryItems = items

        guard let url = components.url else {
            throw SmartAuthError.discoveryFailed(reason: "無法組出授權網址")
        }
        return url
    }

    /// 驗證授權回呼並取出 authorization code。
    public func authorizationCode(from callback: URL) throws -> String {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw SmartAuthError.tokenExchangeFailed(reason: "回呼網址無法解析")
        }
        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )

        if let error = query["error"] {
            if error == "access_denied" {
                throw SmartAuthError.userCancelled
            }
            throw SmartAuthError.authorizationDenied(
                error: error,
                description: query["error_description"]
            )
        }

        // 先驗 state 再取 code：state 不符時 code 本身就不可信，不該拿去換 token。
        guard let returned = query["state"], returned == state else {
            throw SmartAuthError.stateMismatch
        }
        guard let code = query["code"], !code.isEmpty else {
            throw SmartAuthError.tokenExchangeFailed(reason: "回呼沒有帶 authorization code")
        }
        return code
    }

    private static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            fatalError("SecRandomCopyBytes 失敗：OSStatus \(status)")
        }
        return Data(bytes).base64URLEncodedString()
    }
}
