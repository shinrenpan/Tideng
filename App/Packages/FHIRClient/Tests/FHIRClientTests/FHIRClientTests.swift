import Foundation
import Testing
import FHIRCore
@testable import FHIRClient

/// 共用 stub 的靜態狀態，必須序列化執行。
@Suite(.serialized)
struct FHIRClientTests {

    private let base = URL(string: "http://example.org/fhir")!

    private func makeClient() throws -> FHIRClient {
        try FHIRClient(baseURL: base, session: StubURLProtocol.makeSession())
    }

    // MARK: - base URL 是不受信任輸入

    @Test("非 http/https 的 base URL 被拒絕")
    func rejectsNonHTTPScheme() throws {
        for raw in ["file:///etc/passwd", "ftp://example.org/fhir", "javascript:alert(1)"] {
            let url = URL(string: raw)!
            #expect(throws: FHIRClientError.self) {
                _ = try FHIRClient(baseURL: url)
            }
        }
    }

    @Test("http 與 https 都接受")
    func acceptsHTTPAndHTTPS() throws {
        _ = try FHIRClient(baseURL: URL(string: "http://192.168.0.200:8080/fhir")!)
        _ = try FHIRClient(baseURL: URL(string: "https://hapi.fhir.org/baseR4")!)
    }

    // MARK: - 送出的請求

    @Test("search 組出正確的 path、query 與 header")
    func buildsSearchRequest() async throws {
        StubURLProtocol.stub(body: Fixtures.mixedSearchset)
        let client = try makeClient()

        _ = try await client.search(.vitalSigns(patientID: "p1", count: 20))

        let request = try #require(StubURLProtocol.lastRequest)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.path == "/fhir/Observation")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["patient"] == "p1")
        #expect(query["category"] == "vital-signs")
        #expect(query["_sort"] == "-date")
        #expect(query["_count"] == "20")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/fhir+json")
    }

    @Test("沒有 token provider 時不帶 Authorization header")
    func omitsAuthorizationWhenUnauthenticated() async throws {
        StubURLProtocol.stub(body: Fixtures.mixedSearchset)
        let client = try makeClient()

        _ = try await client.search(.patients())

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("有 token 時帶上 Bearer")
    func attachesBearerToken() async throws {
        struct FixedToken: TokenProviding {
            func validToken() async throws -> String? { "abc123" }
        }
        StubURLProtocol.stub(body: Fixtures.mixedSearchset)
        let client = try FHIRClient(
            baseURL: base,
            tokenProvider: FixedToken(),
            session: StubURLProtocol.makeSession()
        )

        _ = try await client.search(.patients())

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    // MARK: - 回應解析

    @Test("從混合 bundle 中依型別取出資源")
    func extractsResourcesByType() async throws {
        StubURLProtocol.stub(body: Fixtures.mixedSearchset)
        let client = try makeClient()

        let bundle = try await client.search(.patients())

        let patients = bundle.resources(of: FHIR.Patient.self)
        let encounters = bundle.resources(of: FHIR.Encounter.self)
        #expect(patients.count == 2)
        #expect(encounters.count == 1)
        #expect(patients.first?.id?.value?.string == "p1")
        #expect(bundle.searchTotal == 2)
    }

    @Test("跟隨 next 連結取下一頁")
    func followsNextLink() async throws {
        StubURLProtocol.stub(body: Fixtures.mixedSearchset)
        let client = try makeClient()
        let first = try await client.search(.patients())

        StubURLProtocol.stub(body: Fixtures.lastPage)
        let second = try await client.nextPage(after: first)

        #expect(second != nil)
        let requestedURL = try #require(StubURLProtocol.lastRequest?.url?.absoluteString)
        #expect(requestedURL == "http://example.org/fhir/Patient?_count=50&page=2")
    }

    @Test("最後一頁沒有 next，回 nil")
    func stopsAtLastPage() async throws {
        StubURLProtocol.stub(body: Fixtures.lastPage)
        let client = try makeClient()
        let bundle = try await client.search(.patients())

        let next = try await client.nextPage(after: bundle)
        #expect(next == nil)
    }

    // MARK: - 錯誤分類

    @Test("401 與 403 都歸類為需要重新登入", arguments: [401, 403])
    func classifiesAuthErrors(status: Int) async throws {
        StubURLProtocol.stub(status: status)
        let client = try makeClient()

        await #expect(throws: FHIRClientError.self) {
            _ = try await client.search(.patients())
        }
        do {
            _ = try await client.search(.patients())
            Issue.record("預期要拋錯")
        } catch let error as FHIRClientError {
            guard case .unauthorized = error else {
                Issue.record("預期 .unauthorized，實際是 \(error)")
                return
            }
        }
    }

    @Test("server 的 OperationOutcome 被解析出來供上層呈現")
    func surfacesOperationOutcome() async throws {
        StubURLProtocol.stub(status: 400, body: Fixtures.operationOutcome)
        let client = try makeClient()

        do {
            _ = try await client.search(.patients())
            Issue.record("預期要拋錯")
        } catch let error as FHIRClientError {
            guard case let .operationOutcome(outcome, status) = error else {
                Issue.record("預期 .operationOutcome，實際是 \(error)")
                return
            }
            #expect(status == 400)
            #expect(outcome.issue.count == 1)
            // server 的說法要能原樣取出——那是唯一講得清楚哪裡不對的來源。
            #expect(error.serverDiagnostics == "不支援的搜尋參數：_sort")
        }
    }

    @Test("無法解析的錯誤回應退回狀態碼")
    func fallsBackToStatusCode() async throws {
        StubURLProtocol.stub(status: 503, body: Data("gateway down".utf8))
        let client = try makeClient()

        do {
            _ = try await client.search(.patients())
            Issue.record("預期要拋錯")
        } catch let error as FHIRClientError {
            guard case let .unexpectedStatus(code) = error else {
                Issue.record("預期 .unexpectedStatus，實際是 \(error)")
                return
            }
            #expect(code == 503)
        }
    }
}
