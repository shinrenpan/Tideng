import Foundation
import Testing
@testable import FHIRCore

struct HumanNameDisplayTests {

    private func name(_ json: String) throws -> FHIR.HumanName {
        try JSONDecoder().decode(FHIR.HumanName.self, from: Data(json.utf8))
    }

    @Test("server 給了 text 就照用，不重新組合")
    func textWins() throws {
        // text 是資料提供方自己排好的順序，比我們猜的準。
        let humanName = try name(#"{"text":"Dr. 王大明","family":"王","given":["大明"]}"#)
        #expect(humanName.displayText == "Dr. 王大明")
    }

    @Test("中文姓名相連，不加空格")
    func cjkJoinsWithoutSpace() throws {
        let humanName = try name(#"{"family":"王","given":["小明"]}"#)
        #expect(humanName.displayText == "王小明")
    }

    @Test("西文姓名以空格分隔，given 在前")
    func latinJoinsWithSpace() throws {
        let humanName = try name(#"{"family":"Smith","given":["John"]}"#)
        #expect(humanName.displayText == "John Smith")
    }

    @Test("完全沒有姓名資料時回 nil")
    func emptyNameIsNil() throws {
        #expect(try name("{}").displayText == nil)
        #expect(try name(#"{"text":""}"#).displayText == nil)
        #expect(try name(#"{"family":"","given":[]}"#).displayText == nil)
    }

    @Test("只有 family 或只有 given 也能組出字串")
    func partialNames() throws {
        #expect(try name(#"{"family":"陳"}"#).displayText == "陳")
        #expect(try name(#"{"given":["美玲"]}"#).displayText == "美玲")
        #expect(try name(#"{"family":"Smith"}"#).displayText == "Smith")
        #expect(try name(#"{"given":["John"]}"#).displayText == "John")
    }

    @Test("多個 given 之間以空格分隔")
    func multipleGivenNames() throws {
        let humanName = try name(#"{"family":"Smith","given":["John","Quincy"]}"#)
        #expect(humanName.displayText == "John Quincy Smith")
    }

    @Test("從姓名陣列取第一個可用的")
    func firstUsableFromArray() throws {
        let names = [try name("{}"), try name(#"{"family":"林","given":["建宏"]}"#)]
        #expect(names.firstDisplayText == "林建宏")
        #expect([FHIR.HumanName]().firstDisplayText == nil)
    }
}
