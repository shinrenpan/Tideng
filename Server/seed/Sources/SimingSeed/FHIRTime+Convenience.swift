import Foundation
import FHIRCore
// seed 直接 import ModelsR4 取用 primitive 型別。
//
// app 端刻意不這麼做——FHIR 的 Observation / Task / Bundle 會撞掉 Swift Observation、
// Swift Concurrency 與 Foundation。但這個 executable 沒有 @Observable、沒有 SwiftUI，
// 也不用 Foundation.Bundle，那三個撞名在這裡構不成問題。
import ModelsR4

extension Date {

    /// 轉成帶時區的 FHIR `dateTime`。
    ///
    /// FHIRModels 在型別層級就要求「有時間就必須有時區」（`DateTime` 的 designated
    /// initializer 註解：You can only have a time if you have a timezone）。
    /// 那正是 HAPI 測試資料違反、害我們整批解碼失敗的規則——用型別建構就不可能再犯。
    func asFHIRDateTime(in timeZone: TimeZone = TimeZone(identifier: "Asia/Taipei")!) -> FHIRPrimitive<DateTime> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: self)

        let date = FHIRDate(
            year: parts.year ?? 2026,
            month: UInt8(parts.month ?? 1),
            day: UInt8(parts.day ?? 1)
        )
        let time = FHIRTime(
            hour: UInt8(parts.hour ?? 0),
            minute: UInt8(parts.minute ?? 0),
            second: Decimal(parts.second ?? 0)
        )
        return FHIRPrimitive(DateTime(date: date, time: time, timezone: timeZone))
    }

    /// 只到日期精度（`birthDate` 用）。
    func asFHIRDate(in timeZone: TimeZone = TimeZone(identifier: "Asia/Taipei")!) -> FHIRPrimitive<FHIRDate> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: self)
        return FHIRPrimitive(FHIRDate(
            year: parts.year ?? 2026,
            month: UInt8(parts.month ?? 1),
            day: UInt8(parts.day ?? 1)
        ))
    }
}

extension FHIR.Quantity {

    /// UCUM 單位的數量。單位系統固定 UCUM——臨床數值的慣例。
    static func ucum(_ value: Double, unit: String, code: String) -> FHIR.Quantity {
        FHIR.Quantity(
            code: FHIRPrimitive(FHIRString(code)),
            system: FHIRPrimitive(FHIRURI(stringLiteral: "http://unitsofmeasure.org")),
            unit: FHIRPrimitive(FHIRString(unit)),
            value: FHIRPrimitive(FHIRDecimal(Decimal(value)))
        )
    }
}

extension FHIR.CodeableConcept {

    static func coded(system: String, code: String, display: String) -> FHIR.CodeableConcept {
        FHIR.CodeableConcept(
            coding: [
                FHIR.Coding(
                    code: FHIRPrimitive(FHIRString(code)),
                    display: FHIRPrimitive(FHIRString(display)),
                    system: FHIRPrimitive(FHIRURI(stringLiteral: system))
                )
            ],
            text: FHIRPrimitive(FHIRString(display))
        )
    }
}

extension FHIR.Reference {

    static func to(_ type: String, id: String) -> FHIR.Reference {
        FHIR.Reference(reference: FHIRPrimitive(FHIRString("\(type)/\(id)")))
    }
}

extension FHIR.Identifier {

    static func make(system: String, value: String) -> FHIR.Identifier {
        FHIR.Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: system)),
            value: FHIRPrimitive(FHIRString(value))
        )
    }
}

extension FHIR.Identifier {

    /// 帶 `MR`（Medical Record Number）標記的病歷號。
    ///
    /// 沒有這個 type coding，client 只能猜哪個 identifier 是病歷號——而猜錯的後果是
    /// 把內部 id 當成病歷號顯示給臨床人員看。
    static func medicalRecord(system: String, value: String) -> FHIR.Identifier {
        FHIR.Identifier(
            system: FHIRPrimitive(FHIRURI(stringLiteral: system)),
            type: .coded(
                system: "http://terminology.hl7.org/CodeSystem/v2-0203",
                code: "MR",
                display: "病歷號"
            ),
            value: FHIRPrimitive(FHIRString(value))
        )
    }
}

extension FHIR.ObservationReferenceRange {

    /// server 提供的參考範圍。app 只認這個來源——內建常數等於由 app 定義何謂正常。
    static func bounds(low: Double?, high: Double?, unit: String, code: String) -> FHIR.ObservationReferenceRange {
        FHIR.ObservationReferenceRange(
            high: high.map { .ucum($0, unit: unit, code: code) },
            low: low.map { .ucum($0, unit: unit, code: code) }
        )
    }
}
