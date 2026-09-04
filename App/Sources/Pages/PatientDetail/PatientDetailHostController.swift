import UIKit
import SwiftUI
import FHIRClient

@MainActor
final class PatientDetailHostController: UIHostingController<PatientDetailView> {

  private let viewModel: PatientDetailViewModel

  /// 身分資料全以 primitive 傳入——呼叫端不需要認識 `PatientDetailViewModel.PatientIdentity`，
  /// 病人清單也不必把自己的 Domain Model 交出來。
  ///
  /// 由清單傳入而非重查：那份資料清單已經有了，重查一次只會讓畫面先空白再填上。
  /// 觀測值則必須自己查——清單沒有那份資料。
  init(
    client: FHIRClient,
    patientID: String,
    name: String,
    gender: String?,
    age: Int?,
    recordNumber: String?
  ) {
    self.viewModel = PatientDetailViewModel(
      client: client,
      patient: .init(id: patientID, name: name, gender: gender, age: age, recordNumber: recordNumber)
    )
    super.init(rootView: PatientDetailView(viewModel: viewModel))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
