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

extension FHIRClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .transport:
            return "無法連線到伺服器"
        case .unauthorized:
            return "登入已失效，請重新登入"
        case let .operationOutcome(outcome, _):
            let details = outcome.issue.compactMap { issue in
                issue.diagnostics?.value?.string ?? issue.details?.text?.value?.string
            }
            return details.isEmpty ? "伺服器拒絕了這個請求" : details.joined(separator: "\n")
        case let .unexpectedStatus(code):
            return "伺服器回應異常（HTTP \(code)）"
        case .decoding:
            return "伺服器回應的格式無法解讀"
        case let .invalidBaseURL(raw):
            return "伺服器位址不正確：\(raw)"
        }
    }
}
