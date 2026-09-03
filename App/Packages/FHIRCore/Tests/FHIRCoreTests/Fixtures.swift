import Foundation

enum Fixtures {

    /// searchset bundle：兩筆 Patient、一筆 Encounter（模擬 _include 混在同一批），並帶 next 連結。
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
        { "resource": { "resourceType": "Patient", "id": "p1" } },
        { "resource": { "resourceType": "Patient", "id": "p2" } },
        { "resource": { "resourceType": "Encounter", "id": "e1", "status": "in-progress",
                        "class": { "code": "AMB" } } }
      ]
    }
    """.utf8)

    /// 沒有 next、也沒有 total 的 bundle。
    ///
    /// 這不是刻意刁難的邊界值——HAPI 公開 server 實測就不回傳 total，
    /// 而主畫面的計數依賴它，所以這個形狀必須被覆蓋。
    static let noTotalNoNext = Data("""
    {
      "resourceType": "Bundle",
      "type": "searchset",
      "link": [ { "relation": "self", "url": "http://example.org/fhir/Patient" } ],
      "entry": [ { "resource": { "resourceType": "Patient", "id": "p9" } } ]
    }
    """.utf8)

    static let empty = Data("""
    { "resourceType": "Bundle", "type": "searchset" }
    """.utf8)
}
