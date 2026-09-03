import SwiftUI

// MARK: - Display Helpers

private extension PatientListViewModel.Slice {

  /// 清單標題。切片名稱一律陳述事實——「超出參考值」而不是「異常」。
  var title: String {
    switch self {
    case .all: String(localized: "Patients")
    case .seenToday: String(localized: "Seen Today")
    case .outOfRange: String(localized: "Outside Reference Range")
    case .onMedication: String(localized: "On Medication")
    }
  }
}

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
    case .male: String(localized: "Male")
    case .female: String(localized: "Female")
    case .other: String(localized: "Other")
    case .unknown: String(localized: "Not recorded")
    }
  }
}

// MARK: - PatientListView

struct PatientListView: View {

  let viewModel: PatientListViewModel

  var body: some View {
    @Bindable var bVM = viewModel

    content()
      .navigationTitle(viewModel.state.slice.title)
      .searchable(text: $bVM.state.keyword, prompt: "Name or record number")
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
          Label("Can't load patients", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            Task { await viewModel.doAction(.view(.retryDidTap)) }
          }
        }

      case .success:
        ContentUnavailableView("No patients on this server", systemImage: "tray")
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
              Text("· \(age) yrs")
            }
            if let recordNumber = patient.recordNumber {
              Text("· \(recordNumber)")
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
#Preview("With data") {
  let vm = PatientListViewModel(client: .preview)
  vm.state.isFirstAppear = false
  vm.state.patients = PatientListViewModel.Patient.mocks
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("Seen today") {
  let vm = PatientListViewModel(client: .preview, sliceIdentifier: "seenToday")
  vm.state.isFirstAppear = false
  vm.state.patients = PatientListViewModel.Patient.mocks
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("Outside reference range") {
  let vm = PatientListViewModel(client: .preview, sliceIdentifier: "outOfRange")
  vm.state.isFirstAppear = false
  vm.state.patients = PatientListViewModel.Patient.mocks
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("On medication") {
  let vm = PatientListViewModel(client: .preview, sliceIdentifier: "onMedication")
  vm.state.isFirstAppear = false
  vm.state.patients = PatientListViewModel.Patient.mocks
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("No search result") {
  let vm = PatientListViewModel(client: .preview)
  vm.state.isFirstAppear = false
  vm.state.patients = PatientListViewModel.Patient.mocks
  vm.state.keyword = "zzz-no-match"
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("Empty") {
  let vm = PatientListViewModel(client: .preview)
  vm.state.isFirstAppear = false
  vm.state.api.loadPatients = .success
  return NavigationStack { PatientListView(viewModel: vm) }
}

#Preview("Load failed") {
  let vm = PatientListViewModel(client: .preview)
  vm.state.isFirstAppear = false
  vm.state.api.loadPatients = .error(message: "Can't reach the server. Check the address and your connection.")
  return NavigationStack { PatientListView(viewModel: vm) }
}
#endif
