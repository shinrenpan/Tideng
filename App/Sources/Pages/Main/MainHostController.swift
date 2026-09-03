import UIKit
import SwiftUI
import FHIRClient
import SmartAuth

@MainActor
final class MainHostController: UIHostingController<MainView> {

  private let viewModel: MainViewModel

  /// 登入完成後才建得起來：`TokenStore` 同時是 session 的持有者與 `FHIRClient` 的 token 來源。
  init(baseURL: URL, tokenStore: TokenStore) {
    // base URL 在登入前已驗證過 scheme，這裡再失敗屬於裝配錯誤。
    guard let client = try? FHIRClient(baseURL: baseURL, tokenProvider: tokenStore) else {
      preconditionFailure("MainHostController 收到不合法的 base URL：\(baseURL)")
    }

    self.viewModel = MainViewModel(
      client: client,
      tokenStore: tokenStore,
      serverHost: baseURL.host ?? baseURL.absoluteString
    )
    // 四個切片的清單各自一個 ViewModel，在這裡建立並由 HostController 持有。
    // 讓 View 自己建或自己快取，狀態會在每次重繪時丟失。
    let patientLists = Dictionary(
      uniqueKeysWithValues: MainViewModel.PatientSlice.allCases.map {
        ($0, PatientListViewModel(client: client, sliceIdentifier: $0.rawValue))
      }
    )
    super.init(rootView: MainView(viewModel: viewModel, patientLists: patientLists))
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

private extension MainHostController {

  func handleRouter(_ router: MainViewModel.Router) {
    switch router {
    case .toSignOut:
      AppRouter.shared.back(from: self)
    }
  }
}
