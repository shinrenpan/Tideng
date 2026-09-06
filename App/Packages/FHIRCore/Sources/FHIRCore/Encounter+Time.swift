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
    /// 需要在 client 端算，**不是因為 server 可能有 bug，而是因為 server 端的
    /// `date=` 就算完全正確也答不出這件事**：
    ///
    /// - 沒有 `period.end` 的就診在 FHIR 裡代表「進行中／結束時間未知」，任何
    ///   `ge` 查詢都會命中它——包含昨天開始、還沒結束的那些。
    /// - 純日期的時區解讀是 R4 未定案的地帶：查詢值與資源欄位有一邊帶了時區，
    ///   規範那句「假設 server 的時區」的前提就不成立。
    ///
    /// 所以「今日就診」這個宣告只能由 client 自己守。
    ///
    /// 時間不明時回 `false`——寧可少算，也不要把不知道時間的資料算進一個宣稱了
    /// 時間範圍的數字。
    func started(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let startedAt else { return false }
        return calendar.isDate(startedAt, inSameDayAs: day)
    }
}
