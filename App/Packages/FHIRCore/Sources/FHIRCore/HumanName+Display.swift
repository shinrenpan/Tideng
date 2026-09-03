import Foundation
import ModelsR4

public extension FHIR.HumanName {

    /// 可顯示的姓名字串；沒有任何可用內容時回 `nil`。
    ///
    /// server 給了 `text` 就照用——那是資料提供方自己排好的順序，比我們從
    /// family/given 猜的準。沒有 `text` 才組合，而組法取決於文字系統：
    /// 中文姓名相連（王小明），西文以空格分隔且 given 在前（John Smith）。
    /// FHIR 沒有欄位表達這個差異，只能從字元判斷。
    var displayText: String? {
        if let text = text?.value?.string, !text.isEmpty {
            return text
        }

        let family = family?.value?.string ?? ""
        let given = (given ?? [])
            .compactMap { $0.value?.string }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !family.isEmpty || !given.isEmpty else { return nil }

        return Self.isCJK(family + given)
            ? family + given
            : [given, family].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 是否含中日韓統一表意文字（含擴充 A 區）。
    private static func isCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }
}

public extension Sequence<FHIR.HumanName> {

    /// 第一個能組出顯示字串的姓名。
    ///
    /// 不是單純取 `first`——資源可能把空的姓名項排在前面，那時該往後找而不是回 `nil`。
    var firstDisplayText: String? {
        lazy.compactMap(\.displayText).first
    }
}
