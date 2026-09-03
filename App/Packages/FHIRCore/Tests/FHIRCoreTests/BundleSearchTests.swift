import Foundation
import Testing
@testable import FHIRCore

struct BundleSearchTests {

    private func decode(_ data: Data) throws -> FHIR.Bundle {
        try JSONDecoder().decode(FHIR.Bundle.self, from: data)
    }

    @Test("依型別從混合 bundle 取出資源")
    func extractsByType() throws {
        let bundle = try decode(Fixtures.mixedSearchset)

        #expect(bundle.resources(of: FHIR.Patient.self).count == 2)
        #expect(bundle.resources(of: FHIR.Encounter.self).count == 1)
        #expect(bundle.resources(of: FHIR.Patient.self).first?.id?.value?.string == "p1")
    }

    @Test("bundle 裡沒有該型別時回空陣列，不是 nil 也不崩潰")
    func missingTypeYieldsEmpty() throws {
        let bundle = try decode(Fixtures.mixedSearchset)
        #expect(bundle.resources(of: FHIR.Observation.self).isEmpty)
    }

    @Test("空 bundle 不會炸")
    func emptyBundleIsSafe() throws {
        let bundle = try decode(Fixtures.empty)
        #expect(bundle.resources(of: FHIR.Patient.self).isEmpty)
        #expect(bundle.nextPageURL == nil)
        #expect(bundle.searchTotal == nil)
    }

    @Test("跟隨 server 給的 next 連結")
    func readsNextLink() throws {
        let bundle = try decode(Fixtures.mixedSearchset)
        #expect(bundle.nextPageURL?.absoluteString == "http://example.org/fhir/Patient?_count=50&page=2")
    }

    @Test("沒有 next 連結時回 nil")
    func noNextLink() throws {
        let bundle = try decode(Fixtures.noTotalNoNext)
        #expect(bundle.nextPageURL == nil)
    }

    @Test("server 有給 total 時讀得到")
    func readsTotal() throws {
        let bundle = try decode(Fixtures.mixedSearchset)
        #expect(bundle.searchTotal == 2)
    }

    @Test("server 沒給 total 時回 nil 而非 0")
    func missingTotalIsNilNotZero() throws {
        // HAPI 公開 server 實測不回 total。若這裡回 0，主畫面的計數會把「不知道」
        // 誤報成「沒有病人」——必須能區分這兩者。
        let bundle = try decode(Fixtures.noTotalNoNext)
        #expect(bundle.searchTotal == nil)
        #expect(bundle.resources(of: FHIR.Patient.self).count == 1)
    }
}
