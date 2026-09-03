import Foundation
import ModelsR4

/// 容忍個別資源不合規的 bundle 解碼。
///
/// 真實的 FHIR server 會回傳不符規格的資料。最常見的是 `dateTime` 帶了時分秒卻沒有
/// 時區偏移（`2026-09-05T08:30:00`）——R4 規格要求必須有，而 FHIRModels 嚴格照規格，
/// 於是整份 bundle 拋錯。
///
/// 實測 HAPI 公開 server：MedicationRequest 查詢 307 筆裡有 1 筆不合規，
/// 那一筆會讓另外 306 筆一起消失。對一個要連得上任何 server 的 app，這不可接受。
public enum FHIRBundleDecoder {

    public struct Result: Sendable {

        /// 只含成功解碼的 entry；`total`、`link` 等 bundle 層級欄位原樣保留。
        public let bundle: FHIR.Bundle

        /// 因不符規格而被跳過的 entry 數。
        ///
        /// 這個數字不能被吞掉——它代表結果不完整，呼叫端據此把計數降級為下限值。
        public let skippedEntries: Int

        /// 成功解碼的 entry 數。
        public let decodedEntries: Int

        public var isPartial: Bool { skippedEntries > 0 }

        public init(bundle: FHIR.Bundle, skippedEntries: Int, decodedEntries: Int) {
            self.bundle = bundle
            self.skippedEntries = skippedEntries
            self.decodedEntries = decodedEntries
        }
    }

    /// - Throws: 當內容根本不是可解碼的 bundle 時，拋出原本的解碼錯誤。
    public static func decode(_ data: Data) throws -> Result {
        let decoder = JSONDecoder()

        // 絕大多數回應是完好的，先走快路徑，不付重組 JSON 的成本。
        if let bundle = try? decoder.decode(FHIR.Bundle.self, from: data) {
            return Result(
                bundle: bundle,
                skippedEntries: 0,
                decodedEntries: bundle.entry?.count ?? 0
            )
        }

        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["entry"] as? [[String: Any]]
        else {
            // 不是 bundle、或沒有 entry 卻仍解不出來——讓原本的錯誤浮上來，
            // 不要用「跳過全部」蓋掉真正的問題。
            return Result(
                bundle: try decoder.decode(FHIR.Bundle.self, from: data),
                skippedEntries: 0,
                decodedEntries: 0
            )
        }

        let kept = entries.filter { entry in
            guard let entryData = try? JSONSerialization.data(withJSONObject: entry) else { return false }
            return (try? decoder.decode(FHIR.BundleEntry.self, from: entryData)) != nil
        }

        object["entry"] = kept
        let cleaned = try JSONSerialization.data(withJSONObject: object)

        return Result(
            bundle: try decoder.decode(FHIR.Bundle.self, from: cleaned),
            skippedEntries: entries.count - kept.count,
            decodedEntries: kept.count
        )
    }
}
