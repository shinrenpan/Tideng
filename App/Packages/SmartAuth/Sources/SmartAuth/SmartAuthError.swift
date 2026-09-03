import Foundation

public enum SmartAuthError: Error, Sendable, Equatable {

    /// discovery 抓不到或格式不對。
    case discoveryFailed(reason: String)

    /// server 不支援這個 app 需要的流程。
    case unsupportedServer(reason: String)

    /// 授權回呼的 `state` 與送出的不符——可能是 CSRF，一律當攻擊處理。
    case stateMismatch

    /// 使用者在授權頁按了取消。
    case userCancelled

    /// server 在 redirect 上回了 error（RFC 6749 §4.1.2.1）。
    case authorizationDenied(error: String, description: String?)

    /// 換 token 失敗。
    case tokenExchangeFailed(reason: String)

    /// refresh 失敗，需要重新登入。
    case sessionExpired

    case transport(message: String)
}

extension SmartAuthError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case let .discoveryFailed(reason):
            return "無法取得伺服器設定：\(reason)"
        case let .unsupportedServer(reason):
            return reason
        case .stateMismatch:
            return "授權回應驗證失敗，請重新登入"
        case .userCancelled:
            return "已取消登入"
        case let .authorizationDenied(error, description):
            return description ?? "授權被拒絕（\(error)）"
        case let .tokenExchangeFailed(reason):
            return "無法取得存取權杖：\(reason)"
        case .sessionExpired:
            return "登入已過期，請重新登入"
        case let .transport(message):
            return "連線失敗：\(message)"
        }
    }
}
