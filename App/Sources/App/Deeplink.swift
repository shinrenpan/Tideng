import UIKit

// MARK: - Deeplink

enum Deeplink {
  case serverSetup
}

// MARK: - URL Parsing

extension Deeplink {
  init?(url: URL) {
    guard url.scheme == "tideng" else { return nil }
    switch url.host {
    case "setup":
      self = .serverSetup
    default:
      return nil
    }
  }
}

// MARK: - HostController Factory

extension Deeplink {
  @MainActor func makeHostController() -> UIViewController {
    switch self {
    case .serverSetup:
      return ServerSetupHostController()
    }
  }
}
