import Foundation

/// FHIR vital-signs profile 要求的 LOINC codes。
///
/// 這些是 profile 強制的，不是我們自己挑的——寫入時 code 不對，server 端 profile 驗證會擋。
public enum LOINC {
    public static let system = "http://loinc.org"

    // MARK: - Vital signs（屬於 vital-signs category）

    public static let vitalSignsPanel = "85353-1"
    public static let heartRate = "8867-4"
    public static let respiratoryRate = "9279-1"
    public static let bodyTemperature = "8310-5"
    public static let bloodPressurePanel = "85354-9"
    public static let systolicBP = "8480-6"
    public static let diastolicBP = "8462-4"
    public static let oxygenSaturation = "59408-5"
    public static let bodyHeight = "8302-2"
    public static let bodyWeight = "29463-7"

    /// 疼痛分數。
    ///
    /// 注意：category 是 `survey` 不是 `vital-signs`——它不屬於 vital-signs profile，
    /// 硬塞進去 profile 驗證會失敗。
    public static let painScore = "72514-3"
}

/// FHIR 標準的 observation category codes。
public enum ObservationCategory {
    public static let system = "http://terminology.hl7.org/CodeSystem/observation-category"

    public static let vitalSigns = "vital-signs"
    public static let survey = "survey"
    public static let laboratory = "laboratory"
}
