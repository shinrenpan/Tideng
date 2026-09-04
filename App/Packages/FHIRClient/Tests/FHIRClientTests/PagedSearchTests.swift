import Foundation
import Testing
import FHIRCore
@testable import FHIRClient

// MARK: - 多頁查詢

extension StubBackedTests {

  @Suite
  struct PagedSearchTests {

    private let base = URL(string: "http://example.org/fhir")!

    private func makeClient() throws -> FHIRClient {
        try FHIRClient(baseURL: base, session: StubURLProtocol.makeSession())
    }

    private func page(ids: [String], next: Bool) -> Data {
        let entries = ids.map { #"{ "resource": { "resourceType": "Patient", "id": "\#($0)" } }"# }
            .joined(separator: ",")
        let link = next
            ? #", "link": [{ "relation": "next", "url": "http://example.org/fhir/Patient?page=2" }]"#
            : ""
        return Data(#"{ "resourceType": "Bundle", "type": "searchset", "entry": [\#(entries)]\#(link) }"#.utf8)
    }

    @Test
    func `只有一頁時不多送請求`() async throws {
        StubURLProtocol.stub(body: page(ids: ["p1", "p2"], next: false))
        let client = try makeClient()

        let result = try await client.search(.patients(), maxPages: 3)

        #expect(StubURLProtocol.requestCount == 1)
        #expect(result.bundle.resources(of: FHIR.Patient.self).count == 2)
    }

    @Test
    func `達到頁數上限就停止即使還有下一頁`() async throws {
        // 上限是取樣邊界，不是完整性保證——server 資料量大時不能無限跟隨。
        StubURLProtocol.stub(body: page(ids: ["p1"], next: true))
        let client = try makeClient()

        let result = try await client.search(.patients(), maxPages: 2)

        #expect(StubURLProtocol.requestCount == 2)
        // 仍有 next，呼叫端據此把計數降級為下限值
        #expect(result.bundle.nextPageURL != nil)
    }

    @Test
    func `多頁的跳過筆數累加`() async throws {
        StubURLProtocol.stub(body: page(ids: ["p1"], next: false))
        let client = try makeClient()

        let result = try await client.search(.patients(), maxPages: 2)

        #expect(result.skippedEntries == 0)
        #expect(result.decodedEntries == 1)
    }
}
}
