import SwiftUI

// MARK: - Display Helpers

// 「性別要顯示成什麼圖示、什麼文字」是 V 層的決策，Domain Model 只帶語意。
private extension PatientListViewModel.PatientGender {

  var symbolName: String {
    switch self {
    case .male: "figure.stand"
    case .female: "figure.stand.dress"
    case .other, .unknown: "person.fill.questionmark"
    }
  }

  var label: String {
    switch self {
    case .male: "男"
    case .female: "女"
    case .other: "其他"
    case .unknown: "未紀錄"
    }
  }
}

// MARK: - PatientListView

struct PatientListView: View {

  let viewModel: PatientListViewModel

  var body: some View {
    @Bindable var bVM = viewModel

    content()
      .navigationTitle("病人")
      .searchable(text: $bVM.state.keyword, prompt: "姓名或病歷號")
      .refreshable { await viewModel.doAction(.view(.pullToRefresh)) }
      .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  // 先看有沒有內容、再看狀態：刷新失敗時不能把使用者眼前的清單換成錯誤畫面。
  @ViewBuilder private func content() -> some View {
    if viewModel.state.patients.isEmpty {
      switch viewModel.state.api.loadPatients {
      case .prepare, .loading:
        ProgressView()

      case let .error(message):
        ContentUnavailableView {
          Label("讀不到病人清單", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("重新載入") {
            Task { await viewModel.doAction(.view(.retryDidTap)) }
          }
        }

      case .success:
        ContentUnavailableView("這個伺服器上沒有病人資料", systemImage: "tray")
      }
    } else {
      ListSection(patients: viewModel.state.filteredPatients)
    }
  }
}

// MARK: - List

private extension PatientListView {

  struct ListSection: View {

    let patients: [PatientListViewModel.Patient]

    var body: some View {
      List(patients) { patient in
        ListRow(patient: patient)
      }
      .listStyle(.plain)
      .overlay {
        // 走得到這裡代表原始清單有資料，那空的就只可能是搜尋沒結果。
        if patients.isEmpty {
          ContentUnavailableView.search
        }
      }
    }
  }

  struct ListRow: View {

    let patient: PatientListViewModel.Patient

    var body: some View {
      HStack(spacing: 12) {
        Image(systemName: patient.gender.symbolName)
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(width: 28)

        VStack(alignment: .leading, spacing: 4) {
          Text(patient.name)
            .font(.body.weight(.medium))

          HStack(spacing: 6) {
            Text(patient.gender.label)
            if let age = patient.age {
              Text("・\(age) 歲")
            }
            if let recordNumber = patient.recordNumber {
              Text("・\(recordNumber)")
                .monospacedDigit()
            }
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 4)
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("有資料") {
  let vm = PatientListViewModel(client: .preview)
  vm.state.isFirstAppear = false
  vm.state.patients = PatientListViewModel.Patient.mocks
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("空清單") {
  let vm = PatientListViewModel(client: .preview)
  vm.state.isFirstAppear = false
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("載入失敗") {
  let vm = PatientListViewModel(client: .preview)
  vm.state.isFirstAppear = false
  vm.state.api.loadPatients = .error(message: "無法連線到伺服器")
  return NavigationStack { PatientListView(viewModel: vm) }
}
#endif
