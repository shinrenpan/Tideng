import Foundation
import FHIRCore

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

    func post<T: FHIR.Resource & Encodable>(
        _ resource: T,
        type: String,
        identifierSystem: String,
        identifierValue: String
    ) async throws -> Outcome {
        var request = URLRequest(url: baseURL.appendingPathComponent(type))
        request.httpMethod = "POST"
        request.setValue("application/fhir+json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
        // 冪等的關鍵：以 client 指定的 identifier 做 conditional create
        request.setValue(
            "identifier=\(identifierSystem)|\(identifierValue)",
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
