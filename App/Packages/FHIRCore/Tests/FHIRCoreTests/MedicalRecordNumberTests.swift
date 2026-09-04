import Foundation
import Testing
@testable import FHIRCore

struct MedicalRecordNumberTests {

    private func identifiers(_ json: String) throws -> [FHIR.Identifier] {
        try JSONDecoder().decode([FHIR.Identifier].self, from: Data(json.utf8))
    }

    private let mrType = #"{ "coding": [{ "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "MR" }] }"#

    @Test
    func `取標記為 MR 的那一個而非第一個`() throws {
        // 第一個是灌資料用的內部 key，第二個才是病歷號。
        let list = try identifiers("""
        [
          { "system": "urn:tideng:demo", "value": "patient-8" },
          { "system": "urn:oid:2.16.886", "value": "A0000008", "type": \(mrType) }
        ]
        """)
        #expect(list.medicalRecordNumber == "A0000008")
    }

    @Test
    func `沒有 MR 標記時回 nil 而不是退而取第一個`() throws {
        // SMART sandbox 的病人只有 UUID。顯示它並標上「病歷號」是誤導。
        let list = try identifiers(#"[{ "value": "73a7d6b7-0310-4fff-9b0b-7891a5e390f5" }]"#)
        #expect(list.medicalRecordNumber == nil)
    }

    @Test
    func `完全沒有 identifier 時回 nil`() throws {
        #expect(try identifiers("[]").medicalRecordNumber == nil)
    }

    @Test
    func `其他 type 的 identifier 不會被誤認`() throws {
        // 身分證字號有自己的 type code，不是病歷號
        let list = try identifiers("""
        [{ "value": "A123456789",
           "type": { "coding": [{ "code": "NNTWN" }] } }]
        """)
        #expect(list.medicalRecordNumber == nil)
    }
}
