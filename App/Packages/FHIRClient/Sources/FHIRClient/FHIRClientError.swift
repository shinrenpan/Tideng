import Foundation
import FHIRCore
import ModelsR4

/// 錯誤三分類，對應三種不同的處理方式。
///
/// 分類本身就是介面約定：呼叫端不必解讀 status code，看 case 就知道該重試、該重新登入、
/// 還是該把 server 的說法顯示給使用者。
public enum FHIRClientError: Error, Sendable {
    /// 網路層失敗。可重試。
    ///
    /// 只留描述不留原始 error：這個值要跨 actor 邊界進到 ViewModel 的 Action，必須 Sendable。
    case transport(message: String)

    /// 401/403。呼叫端應走 refresh 或重新登入。
    case unauthorized(status: Int)

    /// server 回了 OperationOutcome 說明原因。內容應呈現給使用者。
    case operationOutcome(FHIR.OperationOutcome, status: Int)

    /// 非 2xx 且無法解析成 OperationOutcome。
    case unexpectedStatus(Int)

    /// 回應不是合法的 FHIR JSON。
    case decoding(message: String)

    /// base URL 不合法或 scheme 不被接受。
    case invalidBaseURL(String)
}

extension FHIRClientError: CustomStringConvertible {

    /// 給 log 與 debug 用的技術描述，**不是** UI 文案。
    ///
    /// 使用者看到的文字由 app 層依 case 決定——package 是基礎設施，不該持有 UI 文案，
    /// 也不該為了本地化去背一個 resource bundle。
    public var description: String {
        switch self {
        case let .transport(message):
            return "transport failure: \(message)"
        case let .unauthorized(status):
            return "unauthorized (HTTP \(status))"
        case let .operationOutcome(outcome, status):
            let details = outcome.issue.compactMap { issue in
                issue.diagnostics?.value?.string ?? issue.details?.text?.value?.string
            }
            return "server rejected the request (HTTP \(status)): \(details.joined(separator: "; "))"
        case let .unexpectedStatus(code):
            return "unexpected HTTP status \(code)"
        case let .decoding(message):
            return "malformed FHIR response: \(message)"
        case let .invalidBaseURL(raw):
            return "invalid base URL: \(raw)"
        }
    }

    /// server 對這次失敗的說明（`OperationOutcome.issue`）。有的話值得原樣呈現給使用者——
    /// 那是唯一能講清楚「到底哪裡不對」的來源。
    public var serverDiagnostics: String? {
        guard case let .operationOutcome(outcome, _) = self else { return nil }
        let details = outcome.issue.compactMap { issue in
            issue.diagnostics?.value?.string ?? issue.details?.text?.value?.string
        }
        return details.isEmpty ? nil : details.joined(separator: "\n")
    }
}
