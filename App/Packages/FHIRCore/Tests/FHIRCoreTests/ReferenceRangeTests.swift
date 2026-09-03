import Foundation
import Testing
@testable import FHIRCore

struct ReferenceRangeTests {

    /// 依 spec 的範例表格組出 observation。`range` 為 nil 表示 server 未提供參考範圍。
    private func observation(value: String, low: Double?, high: Double?) throws -> FHIR.Observation {
        let bounds = [
            low.map { "\"low\":{\"value\":\($0)}" },
            high.map { "\"high\":{\"value\":\($0)}" }
        ].compactMap { $0 }.joined(separator: ",")

        let referenceRange = bounds.isEmpty ? "" : ",\"referenceRange\":[{\(bounds)}]"

        return try JSONDecoder().decode(FHIR.Observation.self, from: Data("""
        {
          "resourceType": "Observation",
          "status": "final",
          "code": { "coding": [{ "system": "http://loinc.org", "code": "8310-5" }] },
          \(value)
          \(referenceRange)
        }
        """.utf8))
    }

    private func quantity(_ value: Double) -> String {
        "\"valueQuantity\":{\"value\":\(value),\"unit\":\"Cel\"}"
    }

    // MARK: - spec 的範例表格

    @Test("數值對照 server 提供的界限", arguments: [
        (38.9, 36.0 as Double?, 37.5 as Double?, ReferenceRangeStatus.outside),
        (37.0, 36.0, 37.5, .within),
        (35.2, 36.0, nil, .outside),
        (38.9, nil, nil, .indeterminate)
    ])
    func matchesSpecExamples(value: Double, low: Double?, high: Double?, expected: ReferenceRangeStatus) throws {
        let observation = try observation(value: quantity(value), low: low, high: high)
        #expect(observation.referenceRangeStatus == expected)
    }

    // MARK: - 任務要求的其餘輸入

    @Test("只有下界且數值在其上，視為範圍內")
    func aboveLowOnlyIsWithin() throws {
        let observation = try observation(value: quantity(36.8), low: 36.0, high: nil)
        #expect(observation.referenceRangeStatus == .within)
    }

    @Test("只有上界且數值在其下，視為範圍內")
    func belowHighOnlyIsWithin() throws {
        let observation = try observation(value: quantity(37.0), low: nil, high: 37.5)
        #expect(observation.referenceRangeStatus == .within)
    }

    @Test("只有上界且數值超過，視為超出")
    func aboveHighOnlyIsOutside() throws {
        let observation = try observation(value: quantity(39.1), low: nil, high: 37.5)
        #expect(observation.referenceRangeStatus == .outside)
    }

    @Test("非數值型的 value 無法判斷")
    func nonNumericValueIsIndeterminate() throws {
        // 有參考範圍，但 value 是字串——不能因為「有範圍」就強行比較。
        let observation = try observation(value: "\"valueString\":\"positive\"", low: 36.0, high: 37.5)
        #expect(observation.referenceRangeStatus == .indeterminate)
    }

    @Test("有 referenceRange 但界限全空，無法判斷")
    func emptyBoundsAreIndeterminate() throws {
        let observation = try JSONDecoder().decode(FHIR.Observation.self, from: Data("""
        {
          "resourceType": "Observation",
          "status": "final",
          "code": { "coding": [{ "code": "8310-5" }] },
          "valueQuantity": { "value": 38.9 },
          "referenceRange": [{ "text": "see chart" }]
        }
        """.utf8))
        #expect(observation.referenceRangeStatus == .indeterminate)
    }

    // MARK: - 「無法判斷」不得被當成「正常」

    @Test("indeterminate 與 within 是不同的結果")
    func indeterminateIsNotWithin() throws {
        // 這是整個型別存在的理由：若判定回傳 Bool，「沒有參考範圍」會塌成 false，
        // 把「不知道」誤報成「在正常範圍內」。三態必須是三個不同的值。
        let noRange = try observation(value: quantity(38.9), low: nil, high: nil)
        let inRange = try observation(value: quantity(37.0), low: 36.0, high: 37.5)

        #expect(noRange.referenceRangeStatus != inRange.referenceRangeStatus)
        #expect(noRange.referenceRangeStatus == .indeterminate)
        #expect(inRange.referenceRangeStatus == .within)
    }
}
