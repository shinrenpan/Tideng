import Foundation
import Testing
@testable import FHIRCore

struct ObservationTimeTests {

    private func observation(_ effectiveField: String) throws -> FHIR.Observation {
        try JSONDecoder().decode(FHIR.Observation.self, from: Data("""
        {
          "resourceType": "Observation", "status": "final",
          "code": { "coding": [{ "code": "8310-5" }] },
          "valueQuantity": { "value": 37.0 }
          \(effectiveField)
        }
        """.utf8))
    }

    @Test
    func `從 effectiveDateTime 取得紀錄時間`() throws {
        let subject = try observation(#", "effectiveDateTime": "2026-09-03T12:00:00+08:00""#)
        let recordedAt = try #require(subject.recordedAt)

        // 2026-09-03 12:00 台北 = 04:00 UTC
        #expect(abs(recordedAt.timeIntervalSince1970 - 1_788_408_000) < 1)
    }

    @Test
    func `從 period 取得起始時間`() throws {
        let subject = try observation(#", "effectivePeriod": { "start": "2026-09-03T12:00:00+08:00" }"#)
        #expect(subject.recordedAt != nil)
    }

    @Test
    func `沒有時間資訊時回 nil`() throws {
        #expect(try observation("").recordedAt == nil)
    }

    @Test
    func `時間窗的判定`() throws {
        let subject = try observation(#", "effectiveDateTime": "2026-09-03T12:00:00+08:00""#)
        let recordedAt = try #require(subject.recordedAt)

        #expect(subject.recorded(onOrAfter: recordedAt.addingTimeInterval(-3600)))
        #expect(subject.recorded(onOrAfter: recordedAt.addingTimeInterval(3600)) == false)
    }

    @Test
    func `時間不明的觀測值不算在任何時間窗內`() throws {
        // 寧可少算，也不要把不知道時間的資料算進一個宣稱了時間範圍的數字。
        let subject = try observation("")
        #expect(subject.recorded(onOrAfter: .distantPast) == false)
    }
}
