import UIKit
import SwiftUI
import FHIRClient

@MainActor
final class PatientListHostController: UIHostingController<PatientListView> {

  private let viewModel: PatientListViewModel

  /// 以 primitive 接收切片：`client` 是共用的基礎設施，`sliceIdentifier` 是字串。
  /// 呼叫端不需要——也不應該——認識 `PatientListViewModel.Slice`。
  init(client: FHIRClient, sliceIdentifier: String) {
    self.viewModel = PatientListViewModel(client: client, sliceIdentifier: sliceIdentifier)
    super.init(rootView: PatientListView(viewModel: viewModel))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
