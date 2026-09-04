import Foundation
import Testing
import FHIRCore
@testable import FHIRClient

/// 查詢是純資料結構，直接斷言參數即可——不必為了檢查 query 而走一趟網路。
struct FHIRSearchTests {

    /// 固定的「現在」：2026-09-03 12:00:00 UTC。
    private let now = Date(timeIntervalSince1970: 1_788_436_800)

    /// 固定時區，否則測試會依執行機器的設定飄移。
    private var taipei: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    private func query(_ search: FHIRSearch) -> [String: String] {
        Dictionary(search.parameters.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Practitioner 身分

    @Test("依 practitioner 搜尋 role")
    func rolesForPractitioner() {
        let search = FHIRSearch.practitionerRoles(practitionerID: "137594487")

        #expect(search.resourceType == "PractitionerRole")
        #expect(query(search)["practitioner"] == "137594487")
    }

    // MARK: - 切片查詢

    @Test("今日就診以當地日期為界，並帶回病人")
    func encountersToday() {
        let search = FHIRSearch.encountersToday(now: now, calendar: taipei)

        #expect(search.resourceType == "Encounter")
        let parameters = query(search)
        // 2026-09-03 12:00 UTC 在台北是 20:00 同日 → 當地日界是 09-03 00:00+08:00
        //
        // 送的是帶偏移的時刻而不是純日期「2026-09-03」：沒帶時區的日期，
        // 解讀權就落在 server 手上（實測 Siming 當成 UTC，在 +08 差 8 小時）。
        #expect(parameters["date"] == "ge2026-09-03T00:00:00+08:00")
        #expect(parameters["_include"] == "Encounter:subject")
    }

    @Test("跨日界線時取的是當地日期而非 UTC 日期")
    func encountersTodayUsesLocalDate() {
        // 2026-09-03 17:00 UTC 在台北已是 09-04 凌晨 01:00
        let lateEvening = Date(timeIntervalSince1970: 1_788_454_800)
        let search = FHIRSearch.encountersToday(now: lateEvening, calendar: taipei)

        #expect(query(search)["date"] == "ge2026-09-04T00:00:00+08:00")
    }

    @Test("進行中的用藥請求")
    func activeMedicationRequests() {
        let search = FHIRSearch.activeMedicationRequests()

        #expect(search.resourceType == "MedicationRequest")
        let parameters = query(search)
        #expect(parameters["status"] == "active")
        // 病人清單要顯示 Patient 本身，不只是 reference
        #expect(parameters["_include"] == "MedicationRequest:subject")
    }

    @Test("近 24 小時的生命徵象帶時間窗與取樣上限")
    func recentVitalSigns() {
        let search = FHIRSearch.recentVitalSigns(now: now)

        #expect(search.resourceType == "Observation")
        let parameters = query(search)
        #expect(parameters["category"] == "vital-signs")
        // 24 小時前：2026-09-02T12:00:00Z
        #expect(parameters["date"] == "ge2026-09-02T12:00:00Z")
        #expect(parameters["_include"] == "Observation:subject")
        // 對齊 Siming 實際的 maxCount=100。送更大的值會被靜默截斷，
        // 查詢不報錯但計數會低估——那種失敗最難察覺。
        #expect(parameters["_count"] == "100")
    }

    @Test("時間窗可調整，預設 24 小時")
    func vitalSignsWindowIsAdjustable() {
        let search = FHIRSearch.recentVitalSigns(now: now, hours: 48)
        #expect(query(search)["date"] == "ge2026-09-01T12:00:00Z")
    }

    // MARK: - 既有查詢不受影響

    @Test("病人清單查詢維持原樣")
    func patientsUnchanged() {
        let parameters = query(.patients())
        #expect(parameters["_count"] == "50")
        #expect(parameters["_sort"] == "family")
    }
}
