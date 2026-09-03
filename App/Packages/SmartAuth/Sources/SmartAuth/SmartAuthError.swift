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

extension SmartAuthError: CustomStringConvertible {

    /// 給 log 與 debug 用的技術描述，**不是** UI 文案（理由同 `FHIRClientError`）。
    public var description: String {
        switch self {
        case let .discoveryFailed(reason):
            return "SMART discovery failed: \(reason)"
        case let .unsupportedServer(reason):
            return "server does not support the required flow: \(reason)"
        case .stateMismatch:
            return "authorization callback state mismatch (possible CSRF)"
        case .userCancelled:
            return "user cancelled the authorization"
        case let .authorizationDenied(error, description):
            return "authorization denied: \(error)\(description.map { " — \($0)" } ?? "")"
        case let .tokenExchangeFailed(reason):
            return "token exchange failed: \(reason)"
        case .sessionExpired:
            return "session expired, re-authentication required"
        case let .transport(message):
            return "transport failure: \(message)"
        }
    }

    /// server 自己給的說明（`error_description` 等）。有的話值得原樣呈現給使用者。
    public var serverDiagnostics: String? {
        switch self {
        case let .discoveryFailed(reason), let .unsupportedServer(reason),
             let .tokenExchangeFailed(reason):
            return reason
        case let .authorizationDenied(_, description):
            return description
        default:
            return nil
        }
    }
}
