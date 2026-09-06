import Foundation
import FHIRCore
// 需要 FHIRPrimitive／FHIRString 來寫入 resource 的 id。與同 target 的
// ResourceBuilder 一致；App 端「不得 import ModelsR4」的禁令是為了避開
// Observation／Task／Bundle 撞名，seed 沒有那些型別。
import ModelsR4

/// 對 FHIR server 灌資料的最小 client。
///
/// 每次送出都帶 `If-None-Exist`：0 match → 201 建立、1 match → 200 回既有。
/// 這讓腳本可以重跑而不產生重複，也是 `NIS-TECH-SPEC.md` §0 冪等性判斷的第一次真實驗證。
struct FHIRSeedClient {

    enum Outcome {
        case created(id: String)
        case alreadyExists(id: String)
        case rejected(status: Int, detail: String)

        /// server 分配的 id。後續資源要用它組 reference。
        var id: String? {
            switch self {
            case let .created(id), let .alreadyExists(id): id
            case .rejected: nil
            }
        }
    }

    let baseURL: URL
    private let session = URLSession(configuration: .ephemeral)

    /// - Parameter condition: conditional create 的比對條件，預設用 identifier。
    ///
    ///   之所以可覆寫：**server 只在有索引的 search param 上真的過濾**。拿一個沒索引的
    ///   參數當條件，查詢會回傳未過濾的結果、比對到不相干的資源，於是 server 回
    ///   「已存在」而**靜默不寫入**——而且回報成功。實測 Siming 的 PractitionerRole
    ///   只索引 `practitioner`，用 identifier 當條件時第二筆之後全部被吃掉。
    func post<T: FHIR.Resource & Encodable>(
        _ resource: T,
        type: String,
        identifierSystem: String,
        identifierValue: String,
        condition: String? = nil
    ) async throws -> Outcome {
        var request = URLRequest(url: baseURL.appendingPathComponent(type))
        request.httpMethod = "POST"
        request.setValue("application/fhir+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        // 冪等的關鍵：conditional create。條件必須落在 server 真的有索引的參數上。
        request.setValue(
            condition ?? "identifier=\(identifierSystem)|\(identifierValue)",
            forHTTPHeaderField: "If-None-Exist"
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(resource)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .rejected(status: -1, detail: "非 HTTP 回應")
        }

        switch http.statusCode {
        case 201, 200:
            // 201 回新建的資源、200 回既有的——兩者的 body 都帶 id。
            guard let id = Self.resourceID(from: data) else {
                return .rejected(status: http.statusCode, detail: "回應沒有 id，無法建立後續的 reference")
            }
            return http.statusCode == 201 ? .created(id: id) : .alreadyExists(id: id)
        default:
            return .rejected(status: http.statusCode, detail: Self.diagnostics(from: data))
        }
    }

    /// 以指定的 id 寫入資源（FHIR 的 update-as-create）。
    ///
    /// 用途是讓外部系統能長期綁定一個資源——Keycloak 的帳號屬性存的是
    /// `Practitioner/<id>`，而 server 分配的 UUID 每次重灌都會變。
    ///
    /// 與 `post(_:type:identifierSystem:identifierValue:condition:)` 並存而非取代它：
    /// 只有會被外部按身分引用的資源需要固定 id，其餘讓 server 分配是對的——
    /// id 的形狀本來就是 server 的自由。
    ///
    /// - Parameter id: 資源 id。**由本方法寫入 resource 的 `id` 欄位**，呼叫端不需要
    ///   （也不應該）自己設，否則 body 與 URL 不一致時行為由 server 決定。
    func put<T: FHIR.Resource & Encodable>(
        _ resource: T,
        type: String,
        id: String
    ) async throws -> Outcome {
        // FHIR 的 id 語法是 [A-Za-z0-9-.]{1,64}。不合語法的值（尤其含斜線）會
        // 悄悄改變 URL 路徑而不是報錯——那正是我們一直在抓的那種失敗。
        guard Self.isValidFHIRID(id) else {
            return .rejected(status: -1, detail: "「\(id)」不是合法的 FHIR id（限 A-Za-z0-9-. 且 1–64 字）")
        }

        // PUT 是 upsert，回應的狀態碼分不出「新建」與「覆寫」（實測 Siming 兩者都回
        // 200）。先問一次存在與否，報表才不會說謊——我們已經被說謊的報表騙過一次。
        let existedBefore = await exists(type: type, id: id)

        var body = resource
        body.id = FHIRPrimitive(FHIRString(id))

        var request = URLRequest(url: baseURL.appendingPathComponent(type).appendingPathComponent(id))
        request.httpMethod = "PUT"
        request.setValue("application/fhir+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .rejected(status: -1, detail: "非 HTTP 回應")
        }

        switch http.statusCode {
        case 200, 201:
            // 寫入的位址就是 id，不需要從 body 撈——但仍確認 server 沒有改寫它。
            if let returned = Self.resourceID(from: data), returned != id {
                return .rejected(status: http.statusCode, detail: "server 把 id 改成了「\(returned)」")
            }
            return existedBefore ? .alreadyExists(id: id) : .created(id: id)
        default:
            return .rejected(status: http.statusCode, detail: Self.diagnostics(from: data))
        }
    }

    private func exists(type: String, id: String) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent(type).appendingPathComponent(id))
        request.httpMethod = "GET"
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return http.statusCode == 200
    }

    private static func isValidFHIRID(_ id: String) -> Bool {
        guard (1...64).contains(id.count) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")
        return id.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func resourceID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["id"] as? String
    }

    /// server 拒絕時把它自己的說法取出來——那比我們猜的準。
    private static func diagnostics(from data: Data) -> String {
        guard let outcome = try? JSONDecoder().decode(FHIR.OperationOutcome.self, from: data) else {
            return String(decoding: data.prefix(200), as: UTF8.self)
        }
        let details = outcome.issue.compactMap {
            $0.diagnostics?.value?.string ?? $0.details?.text?.value?.string
        }
        return details.isEmpty ? "（server 未提供說明）" : details.joined(separator: "; ")
    }

    func reachable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("metadata"))
        request.timeoutInterval = 10
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }
}

/// 統計每種 resource 的處理結果。
struct SeedTally {
    private(set) var created = 0
    private(set) var existing = 0
    private(set) var rejected: [(identifier: String, detail: String)] = []

    mutating func record(_ outcome: FHIRSeedClient.Outcome, identifier: String) {
        switch outcome {
        case .created: created += 1
        case .alreadyExists: existing += 1
        case let .rejected(status, detail):
            rejected.append((identifier, "HTTP \(status): \(detail)"))
        }
    }

    var isClean: Bool { rejected.isEmpty }
}
