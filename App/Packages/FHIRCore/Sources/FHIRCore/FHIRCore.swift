import ModelsR4

/// FHIR 型別的命名空間。
///
/// 刻意不用 `@_exported import ModelsR4`——FHIR R4 有一批 resource 與 Swift／Foundation 撞名：
///
/// | FHIR resource | 撞到的東西 | 後果 |
/// |---|---|---|
/// | `Observation` | Swift Observation framework | `@Observable` 展開後找不到 `ObservationRegistrar`，直接編不過 |
/// | `Task` | Swift Concurrency 的 `Task` | `Task { }` 會被解析成 FHIR resource |
/// | `Bundle` | `Foundation.Bundle` | 讀不到 app resource |
/// | `Group` / `Media` / `Signature` | SwiftUI 與 Foundation 的同名型別 | 視情境靜默解析錯 |
///
/// 全域 re-export 會讓這些衝突散落到每個 import 的檔案，而且錯誤訊息完全指不到真正的原因
/// （實測：`@Observable` 的報錯是「'Observable' is not a member type of struct 'ModelsR4.Observation'」）。
/// 統一走 `FHIR.` 前綴，衝突就不存在。
public enum FHIR {

    // MARK: - 基底

    public typealias Resource = ModelsR4.Resource
    public typealias Bundle = ModelsR4.Bundle
    public typealias BundleEntry = ModelsR4.BundleEntry
    public typealias OperationOutcome = ModelsR4.OperationOutcome

    // MARK: - MVP 用到的 resource

    public typealias Patient = ModelsR4.Patient
    public typealias Practitioner = ModelsR4.Practitioner
    public typealias PractitionerRole = ModelsR4.PractitionerRole
    public typealias Encounter = ModelsR4.Encounter
    public typealias Location = ModelsR4.Location
    public typealias Observation = ModelsR4.Observation
    public typealias MedicationRequest = ModelsR4.MedicationRequest
    public typealias MedicationAdministration = ModelsR4.MedicationAdministration
    public typealias AuditEvent = ModelsR4.AuditEvent

    // MARK: - 常用資料型別

    public typealias HumanName = ModelsR4.HumanName
    public typealias Identifier = ModelsR4.Identifier
    public typealias CodeableConcept = ModelsR4.CodeableConcept
    public typealias Coding = ModelsR4.Coding
    public typealias Reference = ModelsR4.Reference
    public typealias Quantity = ModelsR4.Quantity
    public typealias AdministrativeGender = ModelsR4.AdministrativeGender
}
