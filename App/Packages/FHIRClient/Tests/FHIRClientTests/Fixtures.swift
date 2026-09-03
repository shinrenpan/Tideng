import Foundation

enum Fixtures {

    /// searchset bundle：兩筆 Patient、一筆 Encounter（模擬 `_include` 混在同一批），並帶 next 連結。
    static let mixedSearchset = Data("""
    {
      "resourceType": "Bundle",
      "type": "searchset",
      "total": 2,
      "link": [
        { "relation": "self", "url": "http://example.org/fhir/Patient?_count=50" },
        { "relation": "next", "url": "http://example.org/fhir/Patient?_count=50&page=2" }
      ],
      "entry": [
        { "resource": { "resourceType": "Patient", "id": "p1",
                        "name": [{ "family": "王", "given": ["小明"] }] } },
        { "resource": { "resourceType": "Patient", "id": "p2",
                        "name": [{ "family": "陳", "given": ["美玲"] }] } },
        { "resource": { "resourceType": "Encounter", "id": "e1", "status": "in-progress",
                        "class": { "code": "AMB" } } }
      ]
    }
    """.utf8)

    /// 沒有 next 連結的最後一頁。
    static let lastPage = Data("""
    {
      "resourceType": "Bundle",
      "type": "searchset",
      "link": [ { "relation": "self", "url": "http://example.org/fhir/Patient" } ],
      "entry": []
    }
    """.utf8)

    static let operationOutcome = Data("""
    {
      "resourceType": "OperationOutcome",
      "issue": [
        { "severity": "error", "code": "invalid", "diagnostics": "不支援的搜尋參數：_sort" }
      ]
    }
    """.utf8)
}
