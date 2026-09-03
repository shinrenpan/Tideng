import Foundation
import FHIRClient
import SmartAuth

/// 把基礎設施層的錯誤轉成使用者看得懂的一句話。
///
/// 文案住在 app 層而不是 package 裡：package 是基礎設施，不該決定使用者看到什麼，
/// 也不該為了本地化去背一個 resource bundle。package 那邊只留給 log 用的技術描述。
enum ErrorMessage {

  static func text(for error: any Error) -> String {
    switch error {
    case let error as FHIRClientError:
      return text(for: error)
    case let error as SmartAuthError:
      return text(for: error)
    default:
      return String(localized: "Something went wrong")
    }
  }

  private static func text(for error: FHIRClientError) -> String {
    switch error {
    case .transport:
      return String(localized: "Can't reach the server. Check the address and your connection.")
    case .unauthorized:
      return String(localized: "Your session has expired. Sign in again to continue.")
    case .operationOutcome:
      // server 自己的說明比任何我們寫的文案都準確，有就照用（不翻譯——那是 server 的話）。
      return error.serverDiagnostics ?? String(localized: "The server rejected this request.")
    case .unexpectedStatus:
      return String(localized: "The server responded in an unexpected way.")
    case .decoding:
      return String(localized: "The server's response couldn't be read as FHIR.")
    case .invalidBaseURL:
      return String(localized: "That server address isn't valid.")
    }
  }

  private static func text(for error: SmartAuthError) -> String {
    switch error {
    case .discoveryFailed:
      return error.serverDiagnostics.map {
        String(localized: "Couldn't read this server's SMART configuration: \($0)")
      } ?? String(localized: "Couldn't read this server's SMART configuration.")
    case .unsupportedServer:
      // 這裡的 reason 已經是可讀的句子（由 SmartAuth 依缺哪項能力產生）。
      return error.serverDiagnostics ?? String(localized: "This server doesn't support the sign-in method this app uses.")
    case .stateMismatch:
      return String(localized: "The sign-in response failed verification. Please try again.")
    case .userCancelled:
      return String(localized: "Sign-in cancelled.")
    case .authorizationDenied:
      return error.serverDiagnostics ?? String(localized: "The server denied this sign-in.")
    case .tokenExchangeFailed:
      return error.serverDiagnostics.map {
        String(localized: "Couldn't complete sign-in: \($0)")
      } ?? String(localized: "Couldn't complete sign-in.")
    case .sessionExpired:
      return String(localized: "Your session has expired. Sign in again to continue.")
    case .transport:
      return String(localized: "Can't reach the server. Check the address and your connection.")
    }
  }
}
