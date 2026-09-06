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

public extension Sequence<FHIR.Identifier> {

    /// 國民身分證統一編號。
    ///
    /// 以 **system** 認定，不以 type coding 的 code 認定。TW Core 把它標成 `NNxxx`，
    /// 真正說明是哪一國的是 code 上的 `identifier-suffix` extension——讀 coding 上的
    /// extension 比比對一個 URI 脆弱得多，而 system 本來就是 identifier 的命名空間。
    ///
    /// 沒有就回 `nil`。**不推導、不重組、不驗證**：這是真人的身分證號，
    /// 顯示一個 server 沒送來的值等於替他發明一組身分。
    var nationalIdentificationNumber: String? {
        first { $0.system?.value?.url.absoluteString == FHIR.twNationalIdentifierSystem }?
            .value?.value?.string
    }
}

public extension FHIR {

    /// 內政部的身分證字號命名空間（TW Core）。
    static let twNationalIdentifierSystem = "http://www.moi.gov.tw"
}
