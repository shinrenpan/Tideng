import UIKit
import SwiftUI

@MainActor
final class ServerSetupHostController: UIHostingController<ServerSetupView> {

  private let viewModel: ServerSetupViewModel

  init() {
    self.viewModel = ServerSetupViewModel()
    super.init(rootView: ServerSetupView(viewModel: viewModel))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    viewModel.onRoute = { [weak self] router in
      self?.handleRouter(router)
    }
  }
}

private extension ServerSetupHostController {

  func handleRouter(_ router: ServerSetupViewModel.Router) {
    switch router {
    case let .toMain(baseURL, store):
      // 用 .fade 而不是 .push：這樣側滑返回會被擋掉（見 mvvmc-navigation 的已知限制）。
      // 登入後不該讓使用者一個手滑就退回登入頁——要離開得明確按登出。
      AppRouter.shared.to(
        MainHostController(baseURL: baseURL, tokenStore: store),
        from: self,
        style: .fade
      )
    }
  }
}
