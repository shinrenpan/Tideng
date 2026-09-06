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
        let value = SeedData.practitionerResourceID(seq: spec.seq)
        var resource = FHIR.Practitioner()
        resource.identifier = [.make(system: SeedData.identifierSystem, value: value)]
        resource.name = [humanName(family: spec.family, given: spec.given)]
        resource.gender = FHIRPrimitive(spec.gender)
        resource.active = FHIRPrimitive(FHIRBool(true))
        return (resource, value)
    }

    // MARK: - PractitionerRole

    static func practitionerRole(
        practitionerID: String,
        spec: SeedData.RoleSpec
    ) -> (resource: FHIR.PractitionerRole, identifier: String) {
        let value = "practitioner-role-\(spec.seq)"
        var resource = FHIR.PractitionerRole()
        resource.identifier = [.make(system: SeedData.identifierSystem, value: value)]
        resource.practitioner = .to("Practitioner", id: practitionerID)
        resource.active = FHIRPrimitive(FHIRBool(true))
        resource.code = [
            FHIR.CodeableConcept(
                coding: [FHIR.Coding(
                    code: FHIRPrimitive(FHIRString(spec.code)),
                    display: FHIRPrimitive(FHIRString(spec.codeDisplay)),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: SeedData.practitionerRoleSystem))
                )],
                text: FHIRPrimitive(FHIRString(spec.text))
            )
        ]
        return (resource, value)
    }

    // MARK: - Patient

    static func patient(_ spec: SeedData.PersonSpec) -> (resource: FHIR.Patient, identifier: String) {
        let value = "patient-\(spec.seq)"
        var resource = FHIR.Patient()
        resource.identifier = [
            .make(system: SeedData.identifierSystem, value: value),
            // 病歷號：診所實際會拿來找人的號碼。必須帶 MR 的 type coding，
            // 否則 client 無從分辨它與上面那個灌資料用的內部 key。
            .medicalRecord(system: SeedData.recordNumberSystem, value: String(format: "A%07d", spec.seq))
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
        start: Date,
        /// 看診結束時間。`nil` 表示病人還在診間。
        ///
        /// 大部分就診都該有 end：小診所不會同時有 8 位病人在診間裡，而且沒有 `end`
        /// 的 period 在 FHIR 裡代表「進行中／結束時間未知」，會被 `date=ge<未來>`
        /// 這類查詢命中——那不是 server 的 bug，是這筆資料真的宣稱自己還沒結束。
        end: Date?
    ) -> (resource: FHIR.Encounter, identifier: String) {
        let value = "encounter-\(seq)"
        var resource = FHIR.Encounter(
            class: FHIR.Coding(
                code: FHIRPrimitive(FHIRString("AMB")),
                display: FHIRPrimitive(FHIRString("門診")),
                system: FHIRPrimitive(FHIRURI(stringLiteral: "http://terminology.hl7.org/CodeSystem/v3-ActCode"))
            ),
            status: FHIRPrimitive(end == nil ? EncounterStatus.inProgress : .finished)
        )
        resource.identifier = [.make(system: SeedData.identifierSystem, value: value)]
        resource.subject = .to("Patient", id: patientID)
        resource.period = Period(
            end: end?.asFHIRDateTime(in: SeedData.timeZone),
            start: start.asFHIRDateTime(in: SeedData.timeZone)
        )
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
        medication: SeedData.MedicationSpec,
        seq: Int,
        authoredOn: Date
    ) -> (resource: FHIR.MedicationRequest, identifier: String) {
        let value = "medication-request-\(seq)"
        var resource = FHIR.MedicationRequest(
            intent: FHIRPrimitive(MedicationRequestIntent.order),
            medication: .codeableConcept(FHIR.CodeableConcept(text: FHIRPrimitive(FHIRString(medication.name)))),
            status: FHIRPrimitive(MedicationrequestStatus.active),
            subject: .to("Patient", id: patientID)
        )
        resource.identifier = [.make(system: SeedData.identifierSystem, value: value)]
        resource.requester = .to("Practitioner", id: practitionerID)
        resource.authoredOn = authoredOn.asFHIRDateTime(in: SeedData.timeZone)
        resource.dosageInstruction = dosageInstruction(for: medication.shape)
        return (resource, value)
    }

    /// 把時程形態轉成 FHIR 的 `dosageInstruction` 陣列。
    ///
    /// 這裡刻意**不**替未指定時間的處方補上 `timeOfDay`。「一天三次」到底是哪三次由
    /// 機構的給藥常規決定，不是這份記錄回答得了的問題——補上去就是把假設寫成處方。
    private static func dosageInstruction(for shape: SeedData.DosageShape) -> [Dosage] {
        switch shape {
        case let .unspecifiedTimes(step), let .explicitTimes(step):
            [dosage(step)]

        case let .asNeeded(reason, dose):
            // 需要時服用沒有時程可言，所以整個 timing 不存在——而不是存在但空著。
            // 空的 timing 會被讀成「有時程但沒填」，那是另一回事。
            {
                var value = Dosage()
                value.asNeeded = .codeableConcept(
                    FHIR.CodeableConcept(text: FHIRPrimitive(FHIRString(reason)))
                )
                value.doseAndRate = [doseAndRate(dose)]
                return [value]
            }()

        case let .tapering(steps):
            // 順序靠 `sequence` 表達，不靠陣列位置——陣列順序在傳輸與儲存中沒有保證。
            steps.enumerated().map { index, step in
                var value = dosage(step)
                value.sequence = FHIRPrimitive(FHIRInteger(Int32(index + 1)))
                return value
            }
        }
    }

    private static func dosage(_ step: SeedData.DosageStep) -> Dosage {
        var repeats = TimingRepeat()
        repeats.frequency = FHIRPrimitive(FHIRPositiveInteger(Int32(step.frequency)))
        repeats.period = FHIRPrimitive(FHIRDecimal(Decimal(step.period)))
        repeats.periodUnit = FHIRPrimitive(FHIRString(step.periodUnit))
        if !step.timesOfDay.isEmpty {
            repeats.timeOfDay = step.timesOfDay.map {
                FHIRPrimitive(FHIRTime(hour: $0.hour, minute: $0.minute, second: 0))
            }
        }
        if let days = step.days {
            var duration = Duration()
            duration.value = FHIRPrimitive(FHIRDecimal(Decimal(days)))
            duration.unit = FHIRPrimitive(FHIRString("day"))
            duration.system = FHIRPrimitive(FHIRURI(stringLiteral: "http://unitsofmeasure.org"))
            duration.code = FHIRPrimitive(FHIRString("d"))
            repeats.bounds = .duration(duration)
        }

        var timing = Timing()
        timing.repeat = repeats

        var value = Dosage()
        value.timing = timing
        value.doseAndRate = [doseAndRate(step.dose)]
        return value
    }

    private static func doseAndRate(_ dose: SeedData.Dose) -> DosageDoseAndRate {
        var value = DosageDoseAndRate()
        value.dose = .quantity(.ucum(dose.value, unit: dose.unit, code: dose.code))
        return value
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
