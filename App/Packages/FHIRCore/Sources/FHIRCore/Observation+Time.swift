import Foundation
import ModelsR4

public extension FHIR.Observation {

    /// 這筆觀測值的紀錄時間。
    ///
    /// 需要在 client 端取得它，是因為**不能假設 server 的 `date` 過濾真的有效**。
    /// 實測 Siming：純日期的形式（`date=ge2026-09-04`）有效，但**值一旦帶時間就被
    /// 靜默忽略**（`date=ge2026-09-04T00:00:00Z` 回傳全部），`Prefer: handling=strict`
    /// 也不報錯。而「近 24 小時」這種時間窗必然要帶時分秒，正好落在失效的那一半——
    /// 隨手用純日期測會得出「它能用」的結論。
    ///
    /// 對一個要連上任何 server 的 app，「server 宣稱支援就相信它」是不安全的假設。
    /// 凡是文案對使用者宣告了範圍（例如「近 24 小時」），就必須在 client 端也守住。
    var recordedAt: Date? {
        switch effective {
        case let .dateTime(value):
            return try? value.value?.asNSDate()
        case let .instant(value):
            return try? value.value?.asNSDate()
        case let .period(period):
            return (try? period.start?.value?.asNSDate()) ?? (try? period.end?.value?.asNSDate())
        case .timing, .none:
            return nil
        }
    }

    /// 這筆觀測值是否落在指定時間點之後。
    ///
    /// 時間不明時回 `false`——寧可少算，也不要把不知道時間的資料算進一個宣稱了時間範圍的數字。
    func recorded(onOrAfter cutoff: Date) -> Bool {
        guard let recordedAt else { return false }
        return recordedAt >= cutoff
    }
}
