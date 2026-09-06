import Foundation
import ModelsR4

public extension FHIR.CodeableConcept {

    /// 這個編碼概念要顯示的文字。
    ///
    /// 順序是 `text` → coding 的 `display` → coding 的 `code`。
    ///
    /// `text` 優先是 FHIR 自己的規定：它是「人給這個概念下的說法」，而 coding 是
    /// 機器讀的。最後才退到 `code`——一個裸碼不好讀，但它仍然是記錄的一部分，
    /// 比空白誠實。三者皆無就回 `nil`，由 UI 決定整段省略。
    ///
    /// **這與生命徵象的名稱不同**：那裡刻意不採用 `display`，改以 LOINC code 查在地化
    /// 名稱，因為同一個項目在不同 server 上的 display 是英文、縮寫或空白。這裡沒有
    /// 那樣的對照表可查（藥名與就診類別沒有固定的碼表），所以只能照著記錄顯示。
    var displayText: String? {
        if let text = text?.value?.string, !text.isEmpty { return text }
        for coding in coding ?? [] {
            if let display = coding.display?.value?.string, !display.isEmpty { return display }
        }
        for coding in coding ?? [] {
            if let code = coding.code?.value?.string, !code.isEmpty { return code }
        }
        return nil
    }
}
