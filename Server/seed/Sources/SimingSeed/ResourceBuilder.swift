import Foundation
import FHIRCore
import ModelsR4
import TWCoreFHIRModels

/// 用型別建構 FHIR 資源，不手寫 JSON。
///
/// 這是刻意的：手寫 JSON 最容易犯的錯正是我們剛被害過的那種——`dateTime` 少了時區。
/// 透過 `DateTime` 的 initializer 建構，型別系統保證「有時間就有時區」。
enum ResourceBuilder {

    // MARK: - Practitioner

    static func practitioner(_ spec: SeedData.PersonSpec) -> (resource: FHIR.Practitioner, identifier: String) {
        let value = "practitioner-\(spec.seq)"
        var resource = FHIR.Practitioner()
        resource.identifier = [.make(system: SeedData.identifierSystem, value: value)]
        resource.name = [humanName(family: spec.family, given: spec.given)]
        resource.gender = FHIRPrimitive(spec.gender)
        resource.active = FHIRPrimitive(FHIRBool(true))
        return (resource, value)
    }

    // MARK: - Patient

    static func patient(_ spec: SeedData.PersonSpec) -> (resource: FHIR.Patient, identifier: String) {
        let value = "patient-\(spec.seq)"
        var resource = FHIR.Patient()
        resource.identifier = [
            .make(system: SeedData.identifierSystem, value: value),
            // 病歷號：診所實際會拿來找人的號碼
            .make(system: SeedData.recordNumberSystem, value: String(format: "A%07d", spec.seq))
        ]
        resource.name = [humanName(family: spec.family, given: spec.given)]
        resource.gender = FHIRPrimitive(spec.gender)
        resource.birthDate = FHIRPrimitive(FHIRDate(
            year: spec.birthYear,
            month: UInt8(spec.birthMonth),
            day: UInt8(spec.birthDay)
        ))
        resource.active = FHIRPrimitive(FHIRBool(true))

        // TW Core：身分證字號帶正確的 system 與 type coding，並宣告 profile
        resource.twCore.idCardNumber = String(format: "A1%08d", spec.seq)
        resource.twCore.declareProfile()

        return (resource, value)
    }

    // MARK: - Encounter

    static func encounter(
        patientID: String,
        practitionerID: String,
        seq: Int,
        start: Date
    ) -> (resource: FHIR.Encounter, identifier: String) {
        let value = "encounter-\(seq)"
        var resource = FHIR.Encounter(
            class: FHIR.Coding(
                code: FHIRPrimitive(FHIRString("AMB")),
                display: FHIRPrimitive(FHIRString("門診")),
                system: FHIRPrimitive(FHIRURI(stringLiteral: "http://terminology.hl7.org/CodeSystem/v3-ActCode"))
            ),
            status: FHIRPrimitive(EncounterStatus.inProgress)
        )
        resource.identifier = [.make(system: SeedData.identifierSystem, value: value)]
        resource.subject = .to("Patient", id: patientID)
        resource.period = Period(start: start.asFHIRDateTime(in: SeedData.timeZone))
        resource.participant = [
            EncounterParticipant(individual: FHIR.Reference.to("Practitioner", id: practitionerID))
        ]
        return (resource, value)
    }

    // MARK: - Observation

    static func observation(
        patientID: String,
        vital: SeedData.VitalSpec,
        value measured: Double,
        recordedAt: Date,
        seq: Int
    ) -> (resource: FHIR.Observation, identifier: String) {
        let identifierValue = "observation-\(seq)"
        var resource = FHIR.Observation(
            code: .coded(system: LOINC.system, code: vital.code, display: vital.display),
            status: FHIRPrimitive(ObservationStatus.final)
        )
        resource.identifier = [.make(system: SeedData.identifierSystem, value: identifierValue)]
        resource.subject = .to("Patient", id: patientID)
        resource.category = [
            .coded(
                system: ObservationCategory.system,
                code: ObservationCategory.vitalSigns,
                display: "生命徵象"
            )
        ]
        resource.effective = .dateTime(recordedAt.asFHIRDateTime(in: SeedData.timeZone))
        resource.value = .quantity(.ucum(measured, unit: vital.unit, code: vital.unitCode))

        // 只有 server 給了範圍，app 才會判斷是否超出——這裡刻意讓一部分不給
        if vital.low != nil || vital.high != nil {
            resource.referenceRange = [
                .bounds(low: vital.low, high: vital.high, unit: vital.unit, code: vital.unitCode)
            ]
        }
        return (resource, identifierValue)
    }

    // MARK: - MedicationRequest

    static func medicationRequest(
        patientID: String,
        practitionerID: String,
        medication: String,
        seq: Int,
        authoredOn: Date
    ) -> (resource: FHIR.MedicationRequest, identifier: String) {
        let value = "medication-request-\(seq)"
        var resource = FHIR.MedicationRequest(
            intent: FHIRPrimitive(MedicationRequestIntent.order),
            medication: .codeableConcept(FHIR.CodeableConcept(text: FHIRPrimitive(FHIRString(medication)))),
            status: FHIRPrimitive(MedicationrequestStatus.active),
            subject: .to("Patient", id: patientID)
        )
        resource.identifier = [.make(system: SeedData.identifierSystem, value: value)]
        resource.requester = .to("Practitioner", id: practitionerID)
        resource.authoredOn = authoredOn.asFHIRDateTime(in: SeedData.timeZone)
        return (resource, value)
    }

    // MARK: - 共用

    /// 中文姓名不帶空格。這也讓 app 端的 CJK 合併規則對著真實資料被驗證一次。
    private static func humanName(family: String, given: String) -> FHIR.HumanName {
        FHIR.HumanName(
            family: FHIRPrimitive(FHIRString(family)),
            given: [FHIRPrimitive(FHIRString(given))],
            use: FHIRPrimitive(NameUse.official)
        )
    }
}
