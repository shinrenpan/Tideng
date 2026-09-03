import Foundation
import ModelsR4

public extension ModelsR4.Bundle {

    /// 從 searchset bundle 取出指定型別的資源。
    ///
    /// `_include` 展開的資源會混在同一個 entry 陣列裡，所以取用時一律指定型別。
    func resources<T: Resource>(of type: T.Type) -> [T] {
        entry?.compactMap { $0.resource?.get(if: type) } ?? []
    }

    /// 分頁的下一頁 URL。
    ///
    /// 跟隨 server 給的連結，不自己拼 offset——server 端可能是 cursor 分頁。
    var nextPageURL: URL? {
        guard let raw = link?.first(where: { $0.relation.value?.string == "next" })?.url.value?.url
        else { return nil }
        return raw
    }

    /// server 回報的搜尋總筆數（`Bundle.total`）。server 可以不給。
    var searchTotal: Int? {
        total?.value.map { Int($0.integer) }
    }
}
