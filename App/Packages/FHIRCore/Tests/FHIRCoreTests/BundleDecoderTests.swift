import Foundation
import Testing
@testable import FHIRCore

struct BundleDecoderTests {

    /// 不合規的 dateTime：FHIR R4 要求帶了時分秒就必須帶時區偏移。
    /// 這不是虛構的邊界值——HAPI 公開 server 上大量存在。
    private let malformed = #"""
    { "resource": { "resourceType": "Encounter", "id": "bad", "status": "finished",
      "class": { "code": "AMB" }, "period": { "start": "2026-09-05T08:30:00" } } }
    """#

    private func good(_ id: String) -> String {
        #"{ "resource": { "resourceType": "Patient", "id": "\#(id)" } }"#
    }

    private func bundle(_ entries: [String], total: Int? = nil) -> Data {
        let totalField = total.map { "\"total\": \($0)," } ?? ""
        return Data("""
        { "resourceType": "Bundle", "type": "searchset", \(totalField)
          "entry": [\(entries.joined(separator: ","))] }
        """.utf8)
    }

    @Test
    func `全部合規時直接解碼不付重組成本`() throws {
        let result = try FHIRBundleDecoder.decode(bundle([good("p1"), good("p2")]))

        #expect(result.skippedEntries == 0)
        #expect(result.isPartial == false)
        #expect(result.bundle.resources(of: FHIR.Patient.self).count == 2)
    }

    @Test
    func `一筆壞資料不得毀掉其餘三百筆`() throws {
        // 實測數據：MedicationRequest 查詢是 1/307 筆不合規。
        var entries = (1...306).map { good("p\($0)") }
        entries.insert(malformed, at: 150)

        let result = try FHIRBundleDecoder.decode(bundle(entries))

        #expect(result.skippedEntries == 1)
        #expect(result.isPartial)
        #expect(result.bundle.resources(of: FHIR.Patient.self).count == 306)
    }

    @Test
    func `跳過多筆時全部計入`() throws {
        let result = try FHIRBundleDecoder.decode(bundle([malformed, good("p1"), malformed, good("p2")]))

        #expect(result.skippedEntries == 2)
        #expect(result.bundle.resources(of: FHIR.Patient.self).count == 2)
    }

    @Test
    func `Bundle 本身的欄位在重組後保留`() throws {
        // total 與 link 決定計數是精確值還是下限值，重組時不能弄丟。
        let data = Data("""
        { "resourceType": "Bundle", "type": "searchset", "total": 307,
          "link": [{ "relation": "next", "url": "https://example.org/fhir/Patient?page=2" }],
          "entry": [\(malformed),\(good("p1"))] }
        """.utf8)

        let result = try FHIRBundleDecoder.decode(data)

        #expect(result.bundle.searchTotal == 307)
        #expect(result.bundle.nextPageURL != nil)
        #expect(result.skippedEntries == 1)
    }

    @Test
    func `完全沒有 entry 的 bundle 照常解碼`() throws {
        let result = try FHIRBundleDecoder.decode(Data(#"{ "resourceType": "Bundle", "type": "searchset" }"#.utf8))

        #expect(result.skippedEntries == 0)
        #expect(result.bundle.entry == nil)
    }

    @Test
    func `全部 entry 都壞掉時仍回傳空 bundle 並如實回報跳過數`() throws {
        // 呼叫端需要能分辨「全部壞掉」與「server 真的沒有資料」——前者不該報成 0。
        let result = try FHIRBundleDecoder.decode(bundle([malformed, malformed]))

        #expect(result.skippedEntries == 2)
        #expect(result.bundle.resources(of: FHIR.Patient.self).isEmpty)
        #expect(result.decodedEntries == 0)
    }

    @Test
    func `根本不是 bundle 時把原本的解碼錯誤拋出來`() {
        #expect(throws: (any Error).self) {
            try FHIRBundleDecoder.decode(Data(#"{ "resourceType": "Patient", "id": "p1" }"#.utf8))
        }
    }
}
