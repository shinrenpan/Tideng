import Foundation
import FHIRCore
import ModelsR4

/// FHIR R4 REST client。
///
/// 對 auth 一無所知——token 由外部透過 `TokenProviding` 注入。
public actor FHIRClient {

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: any TokenProviding
    private let decoder = JSONDecoder()

    /// - Parameter baseURL: 使用者輸入的 FHIR base URL。視為不受信任輸入，只接受 http/https。
    public init(
        baseURL: URL,
        tokenProvider: any TokenProviding = NoAuthentication(),
        session: URLSession = .shared
    ) throws {
        guard let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw FHIRClientError.invalidBaseURL(baseURL.absoluteString)
        }
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - 查詢

    public func search(_ search: FHIRSearch) async throws -> FHIR.Bundle {
        try await fetch(FHIR.Bundle.self, from: url(for: search))
    }

    /// 跟隨 server 給的 `next` 連結取下一頁；沒有下一頁時回 `nil`。
    ///
    /// 不自己拼 offset——server 可能是 cursor 分頁。
    public func nextPage(after bundle: FHIR.Bundle) async throws -> FHIR.Bundle? {
        guard let next = bundle.nextPageURL else { return nil }
        return try await fetch(FHIR.Bundle.self, from: next)
    }

    public func read<T: FHIR.Resource>(_ type: T.Type, id: String) async throws -> T {
        let resourceType = String(describing: type)
        let target = baseURL
            .appendingPathComponent(resourceType)
            .appendingPathComponent(id)
        return try await fetch(type, from: target)
    }

    // MARK: - 內部

    private func url(for search: FHIRSearch) throws -> URL {
        let target = baseURL.appendingPathComponent(search.resourceType)
        guard var components = URLComponents(url: target, resolvingAgainstBaseURL: false) else {
            throw FHIRClientError.invalidBaseURL(target.absoluteString)
        }
        components.queryItems = search.parameters.map { URLQueryItem(name: $0.name, value: $0.value) }
        guard let url = components.url else {
            throw FHIRClientError.invalidBaseURL(target.absoluteString)
        }
        return url
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        if let token = try await tokenProvider.validToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FHIRClientError.transport(message: String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw FHIRClientError.unexpectedStatus(-1)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw error(for: http.statusCode, body: data)
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw FHIRClientError.decoding(message: String(describing: error))
        }
    }

    /// 把非 2xx 的回應轉成分類過的錯誤。
    ///
    /// server 通常會在 body 附上 OperationOutcome 說明原因，能解出來就用它——
    /// 那是唯一能告訴使用者「到底哪裡不對」的東西。
    private func error(for status: Int, body: Data) -> FHIRClientError {
        if status == 401 || status == 403 {
            return .unauthorized(status: status)
        }
        if let outcome = try? decoder.decode(FHIR.OperationOutcome.self, from: body) {
            return .operationOutcome(outcome, status: status)
        }
        return .unexpectedStatus(status)
    }
}
