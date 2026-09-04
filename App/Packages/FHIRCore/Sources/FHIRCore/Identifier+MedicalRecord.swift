import Foundation
import ModelsR4

public extension Sequence<FHIR.Identifier> {

    /// 病歷號：標記為 `MR`（Medical Record Number）的那一個。
    ///
    /// 不能取「第一個 identifier」——FHIR 資源上常有多個，而第一個往往是內部識別碼。
    /// 實測：Siming 的 seed 資料第一個是灌資料用的 key，SMART sandbox 的第一個是 UUID。
    /// 兩者都被當成病歷號顯示過。
    ///
    /// 沒有標記為 MR 的就回 `nil`，UI 據此整段省略。顯示一個內部 id 並標上「病歷號」
    /// 是誤導——那個標籤宣稱了語意，填不符合的值進去比留白更糟。
    var medicalRecordNumber: String? {
        first { identifier in
            identifier.type?.coding?.contains { coding in
                coding.code?.value?.string == "MR"
            } ?? false
        }?.value?.value?.string
    }
}
