import Foundation

/// SMART App Launch 的網路操作：discovery、換 token、refresh。
///
/// 不碰 UI、不碰儲存——那是 `SmartSession` 與 `TokenStore` 的事，
/// 拆開才能用 stub server 完整測試協定層。
public struct SmartAuthClient: Sendable {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Discovery

    public func discover(baseURL: URL) async throws -> SmartConfiguration {
        let url = baseURL.appendingPathComponent(".well-known/smart-configuration")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            // 沒有 well-known 時的 fallback（讀 CapabilityStatement 的 security extension）
            // MVP 不做，回明確訊息而不是安靜降級——安靜降級只會讓問題延後爆炸。
            throw SmartAuthError.discoveryFailed(
                reason: "伺服器沒有提供 SMART 設定（HTTP \(response.statusCode)）"
            )
        }

        do {
            return try JSONDecoder().decode(SmartConfiguration.self, from: data)
        } catch {
            throw SmartAuthError.discoveryFailed(reason: "設定格式無法解讀")
        }
    }

    // MARK: - Token

    public func exchangeCode(_ code: String, for request: AuthorizationRequest) async throws -> TokenResponse {
        try await postToken(
            endpoint: request.configuration.tokenEndpoint,
            parameters: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": request.redirectURI.absoluteString,
                "client_id": request.clientID,
                // public client 沒有 secret，靠這個證明是同一個發起者。
                "code_verifier": request.pkce.verifier
            ]
        )
    }

    public func refresh(
        refreshToken: String,
        configuration: SmartConfiguration,
        clientID: String
    ) async throws -> TokenResponse {
        try await postToken(
            endpoint: configuration.tokenEndpoint,
            parameters: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID
            ]
        )
    }

    // MARK: - 內部

    private func postToken(endpoint: URL, parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncoded(parameters)

        let (data, response) = try await send(request)

        guard (200..<300).contains(response.statusCode) else {
            throw SmartAuthError.tokenExchangeFailed(reason: Self.oauthErrorMessage(from: data, status: response.statusCode))
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw SmartAuthError.tokenExchangeFailed(reason: "回應格式無法解讀")
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SmartAuthError.transport(message: "非 HTTP 回應")
            }
            return (data, http)
        } catch let error as SmartAuthError {
            throw error
        } catch {
            throw SmartAuthError.transport(message: String(describing: error))
        }
    }

    /// OAuth 2 的錯誤回應（RFC 6749 §5.2）。有 `error_description` 就用它——
    /// 那是 server 唯一會說人話的地方。
    private static func oauthErrorMessage(from data: Data, status: Int) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "HTTP \(status)"
        }
        if let description = json["error_description"] as? String, !description.isEmpty {
            return description
        }
        if let error = json["error"] as? String {
            return error
        }
        return "HTTP \(status)"
    }

    /// form-urlencoded 的編碼。
    ///
    /// 只放行 unreserved 字元（RFC 3986）。特別是 `+` 一定要編碼成 `%2B`——
    /// 在 form-urlencoded 裡它代表空格，authorization code 含 `+` 時不編碼會直接送錯值，
    /// 而且 server 只會回一個沒頭沒尾的 invalid_grant。
    static func formURLEncoded(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        let body = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        return Data(body.utf8)
    }
}
