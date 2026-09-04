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

    /// - Returns: 解碼結果，含因不符 FHIR 規格而被跳過的 entry 數。
    ///   個別資源不合規時不會讓整批失敗——真實 server 的資料品質參差，
    ///   一筆壞資料毀掉三百筆好資料是不可接受的。
    public func search(_ search: FHIRSearch) async throws -> FHIRBundleDecoder.Result {
        try await fetchBundle(from: url(for: search))
    }

    /// 跟隨 `next` 連結取回多頁，合併成單一結果。
    ///
    /// 需要它是因為不能假設 server 支援時間過濾或排序。實測 Siming：`date` 參數宣稱
    /// 支援卻完全無效，而預設排序也不是時間序——於是「近 24 小時超出參考值」如果只取
    /// 第一頁，抽到的那 100 筆可能完全不含異常值，卡片就會安靜地顯示 0。
    ///
    /// - Parameter maxPages: 最多取幾頁。這是取樣邊界，不是完整性保證——
    ///   仍有下一頁時結果會標記為不完整，呼叫端據此把計數降級為下限值。
    public func search(_ search: FHIRSearch, maxPages: Int) async throws -> FHIRBundleDecoder.Result {
        precondition(maxPages >= 1, "至少要取一頁")

        var results: [FHIRBundleDecoder.Result] = [try await self.search(search)]

        while results.count < maxPages, let next = results.last?.bundle.nextPageURL {
            results.append(try await fetchBundle(from: next))
        }

        return Self.merge(results)
    }

    /// 把多頁合併成單一 bundle，讓呼叫端不必知道分頁的存在。
    private static func merge(_ results: [FHIRBundleDecoder.Result]) -> FHIRBundleDecoder.Result {
        guard let first = results.first else {
            return .init(bundle: FHIR.Bundle(type: FHIRPrimitive(BundleType.searchset)), skippedEntries: 0, decodedEntries: 0)
        }
        guard results.count > 1 else { return first }

        var merged = FHIR.Bundle(type: FHIRPrimitive(BundleType.searchset))
        merged.entry = results.flatMap { $0.bundle.entry ?? [] }
        // total 沿用 server 的說法；還有沒有下一頁看最後一頁
        merged.total = first.bundle.total
        merged.link = results.last?.bundle.link

        return .init(
            bundle: merged,
            skippedEntries: results.reduce(0) { $0 + $1.skippedEntries },
            decodedEntries: results.reduce(0) { $0 + $1.decodedEntries }
        )
    }

    /// 跟隨 server 給的 `next` 連結取下一頁；沒有下一頁時回 `nil`。
    ///
    /// 不自己拼 offset——server 可能是 cursor 分頁。
    public func nextPage(after bundle: FHIR.Bundle) async throws -> FHIRBundleDecoder.Result? {
        guard let next = bundle.nextPageURL else { return nil }
        return try await fetchBundle(from: next)
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

    private func fetchBundle(from url: URL) async throws -> FHIRBundleDecoder.Result {
        let payload = try await data(from: url)
        do {
            return try FHIRBundleDecoder.decode(payload)
        } catch {
            throw FHIRClientError.decoding(message: String(describing: error))
        }
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let payload = try await data(from: url)
        do {
            return try decoder.decode(type, from: payload)
        } catch {
            throw FHIRClientError.decoding(message: String(describing: error))
        }
    }

    private func data(from url: URL) async throws -> Data {
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

        return data
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
