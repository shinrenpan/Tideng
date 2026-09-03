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
    nonisolated(unsafe) private static var bodies: [Data] = []
    nonisolated(unsafe) private static var delay: TimeInterval = 0

    /// - Parameter delay: 人為延遲。測併發時需要它把競態窗口撐開，
    ///   否則請求快到彼此不會重疊，測不出序列化有沒有生效。
    static func stub(status: Int = 200, body: Data = Data(), delay: TimeInterval = 0) {
        lock.withLock {
            Self.status = status
            Self.body = body
            Self.delay = delay
            Self.recorded = []
            Self.bodies = []
        }
    }

    static var requestCount: Int {
        lock.withLock { recorded.count }
    }

    static var lastRequest: URLRequest? {
        lock.withLock { recorded.last }
    }

    /// `URLProtocol` 收到的 request 會把 httpBody 搬到 httpBodyStream，所以另外記一份。
    static var lastBody: Data? {
        lock.withLock { bodies.last }
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
        let capturedBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return data
        }

        let (status, body, delay) = Self.lock.withLock {
            Self.recorded.append(request)
            if let capturedBody { Self.bodies.append(capturedBody) }
            return (Self.status, Self.body, Self.delay)
        }

        guard delay == 0 else {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.finish(status: status, body: body)
            }
            return
        }
        finish(status: status, body: body)
    }

    private func finish(status: Int, body: Data) {
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
