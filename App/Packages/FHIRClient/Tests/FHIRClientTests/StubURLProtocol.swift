import Foundation

/// 攔截 `URLSession` 請求，回傳預設好的回應，並記錄實際送出的 request。
///
/// 用它而不是把 URL 組裝抽成純函式來測——這樣測到的是「真的送出去長什麼樣」，
/// 涵蓋 header、query 編碼與狀態碼處理整條路徑。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func stub(status: Int = 200, body: Data = Data()) {
        lock.withLock {
            Self.status = status
            Self.body = body
            Self.recorded = []
        }
    }

    static var lastRequest: URLRequest? {
        lock.withLock { recorded.last }
    }

    /// 專用於測試的 session，只走這個 stub。
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.lock.withLock {
            Self.recorded.append(request)
            return (Self.status, Self.body)
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/fhir+json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
