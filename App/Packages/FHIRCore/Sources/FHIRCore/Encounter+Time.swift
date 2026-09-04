import Foundation
import ModelsR4

public extension FHIR.Encounter {

    /// 就診的開始時間。
    var startedAt: Date? {
        try? period?.start?.value?.asNSDate()
    }

    /// 這次就診是否在指定的當地日期開始。
    ///
    /// 「今日就診」對診所的意思是「今天來的病人」，所以判準是**開始日期**，
    /// 不是 period 與今天有沒有交集——昨天來、還沒結束的病人不算今天來的。
    ///
    /// 需要在 client 端算，是因為不能假設 server 的 `date` 過濾有效。實測 Siming：
    /// `Encounter?date=` 完全沒有作用（連純日期的形式都不生效），送
    /// `date=ge2099-01-01` 照樣回傳全部。而且沒有 `period.end` 的就診在 FHIR 裡
    /// 代表「進行中」，本來就會被 `ge` 命中——即使 server 的過濾是對的，
    /// 「今日就診」這個宣告仍然只能由 client 自己守。
    ///
    /// 時間不明時回 `false`——寧可少算，也不要把不知道時間的資料算進一個宣稱了
    /// 時間範圍的數字。
    func started(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let startedAt else { return false }
        return calendar.isDate(startedAt, inSameDayAs: day)
    }
}
