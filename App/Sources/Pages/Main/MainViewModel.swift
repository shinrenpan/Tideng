import Foundation
import SmartAuth

@Observable
@MainActor
final class MainViewModel {

  var state: State = .init()

  @ObservationIgnored
  var onRoute: (@MainActor (Router) -> Void)?

  @ObservationIgnored
  private let tokenStore: TokenStore

  init(tokenStore: TokenStore, serverHost: String) {
    self.tokenStore = tokenStore
    self.state.serverHost = serverHost
  }

  func doAction(_ action: Action) async {
    switch action {
    case let .view(action):
      await handleViewAction(action)
    }
  }
}

// MARK: - Actions

extension MainViewModel {

  enum Action: Sendable {
    case view(ViewAction)
  }

  enum ViewAction: Sendable {
    case isFirstAppear
    case menuItemDidTap(MenuItem)
    case signOutDidTap
  }

  enum Router: Equatable, Sendable {
    case toSignOut
  }
}

// MARK: - View Actions

private extension MainViewModel {

  func handleViewAction(_ action: ViewAction) async {
    switch action {
    case .isFirstAppear:
      state.practitionerReference = await tokenStore.currentTokens?.fhirUser

    case let .menuItemDidTap(item):
      guard item.isAvailable else { return }
      state.selection = item

    case .signOutDidTap:
      await tokenStore.signOut()
      onRoute?(.toSignOut)
    }
  }
}
