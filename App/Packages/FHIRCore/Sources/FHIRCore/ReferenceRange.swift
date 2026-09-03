import Foundation
import ModelsR4

/// 一筆觀測值相對於 server 提供的參考範圍的位置。
///
/// 刻意不是 `Bool`，也不是 `Bool?`：「沒有參考範圍可比」與「在範圍內」是**不同的事實**，
/// 但 `Bool` 只有兩格，第三種情況必然被塞進其中一格——而習慣上會塞進 `false`，
/// 於是「不知道」被靜默地誤報成「正常」。三個具名 case 讓呼叫端無法迴避這個區分。
public enum ReferenceRangeStatus: Sendable, Equatable {

    /// 數值落在 server 提供的界限之外。
    case outside

    /// 數值落在 server 提供的界限之內。
    case within

    /// 無法判斷：server 沒有提供參考範圍，或數值不是可比較的量。
    ///
    /// **不得視為 `within`。** 把「沒有依據可判斷」當成「正常」是臨床判讀，
    /// 不是事實陳述。
    case indeterminate
}

public extension FHIR.Observation {

    /// 這筆觀測值相對於 **server 提供的** 參考範圍的位置。
    ///
    /// app 不內建任何參考值。定義何謂正常屬於臨床判讀，而這個 app 只陳述事實——
    /// 所以 server 沒給範圍時回 `.indeterminate`，不是 `.within`。
    ///
    /// 有多組 referenceRange 時只採用第一組帶界限的。要選對哪一組需要年齡、性別等
    /// context，而那個選擇本身就是判讀，超出本 app 的範圍。
    var referenceRangeStatus: ReferenceRangeStatus {
        guard case let .quantity(measurement) = value,
              let measured = measurement.value?.value?.decimal
        else { return .indeterminate }

        guard let range = referenceRange?.first(where: {
            $0.low?.value?.value != nil || $0.high?.value?.value != nil
        }) else { return .indeterminate }

        if let low = range.low?.value?.value?.decimal, measured < low {
            return .outside
        }
        if let high = range.high?.value?.value?.decimal, measured > high {
            return .outside
        }
        return .within
    }
}
