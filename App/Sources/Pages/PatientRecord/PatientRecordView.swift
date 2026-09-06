import SwiftUI

// MARK: - Display Helpers

private extension PatientRecordViewModel.Gender {

  var label: String {
    switch self {
    case .male: String(localized: "Male")
    case .female: String(localized: "Female")
    case .other: String(localized: "Other")
    case .unknown: String(localized: "Unknown")
    }
  }
}

private extension DateComponents {

  /// 生日的顯示文字，**精度照著記錄走**。
  ///
  /// FHIR 的 `date` 允許只有年、或只有年月。補上不存在的月日等於宣稱記錄沒說的事，
  /// 所以少一級就少顯示一級。
  var recordedDateText: String? {
    guard let year else { return nil }
    guard let month else { return String(year) }
    guard let day else { return String(format: "%d-%02d", year, month) }
    return String(format: "%d-%02d-%02d", year, month, day)
  }
}

// MARK: - PatientRecordView

struct PatientRecordView: View {

  let viewModel: PatientRecordViewModel

  var body: some View {
    content()
      .navigationTitle(viewModel.state.patient.name)
      .navigationBarTitleDisplayMode(.inline)
      .refreshable { await viewModel.doAction(.view(.pullToRefresh)) }
      .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  // 先看有沒有內容、再看狀態：刷新失敗時不能把眼前的資料換成錯誤畫面。
  @ViewBuilder private func content() -> some View {
    if let record = viewModel.state.record {
      RecordSection(record: record)
    } else {
      switch viewModel.state.api.loadRecord {
      case .prepare, .loading:
        ProgressView()

      case let .error(message):
        ContentUnavailableView {
          Label("Can't load this record", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            Task { await viewModel.doAction(.view(.retryDidTap)) }
          }
        }

      case .success:
        ContentUnavailableView("No record for this patient", systemImage: "person.crop.circle.badge.questionmark")
      }
    }
  }
}

// MARK: - Record

private extension PatientRecordView {

  /// 純展示，沒有互動——不需要 `enum Action`。
  struct RecordSection: View {

    let record: PatientRecordViewModel.Record

    var body: some View {
      List {
        Section {
          if let name = record.name {
            LabeledContent("Name", value: name)
          }
          if let gender = record.gender {
            LabeledContent("Gender", value: gender.label)
          }
          // 生日與年齡同進退：年齡是從生日推導的，沒有生日就沒有年齡可說。
          if let birthDate = record.birthDate?.recordedDateText {
            LabeledContent("Date of Birth", value: birthDate)
            if let age = record.age() {
              LabeledContent("Age", value: String(localized: "\(age) yrs"))
            }
          }
        } header: {
          Text("Identity")
        }

        Section {
          if let recordNumber = record.recordNumber {
            LabeledContent("Medical Record Number", value: recordNumber)
              .monospacedDigit()
          }
          if let nationalIdentifier = record.nationalIdentifier {
            LabeledContent("National ID", value: nationalIdentifier)
              .monospacedDigit()
          }
          if record.recordNumber == nil, record.nationalIdentifier == nil {
            Text("No identifier on this record could be recognised by type.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Identifiers")
        } footer: {
          // 說明為什麼有些號碼沒有出現——沉默會讓人以為 app 漏掉了。
          Text("Only identifiers labelled with a known type are shown.")
        }
      }
      .listStyle(.insetGrouped)
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("With record") {
  let vm = PatientRecordViewModel(client: .preview, patient: .init(id: "p1", name: "王志明"))
  vm.state.isFirstAppear = false
  vm.state.record = PatientRecordViewModel.Record.mock
  vm.state.api.loadRecord = .success
  return NavigationStack { PatientRecordView(viewModel: vm) }
}

#Preview("Sparse record") {
  let vm = PatientRecordViewModel(client: .preview, patient: .init(id: "p2", name: "陳美玲"))
  vm.state.isFirstAppear = false
  vm.state.record = PatientRecordViewModel.Record.sparseMock
  vm.state.api.loadRecord = .success
  return NavigationStack { PatientRecordView(viewModel: vm) }
}

#Preview("Not found") {
  let vm = PatientRecordViewModel(client: .preview, patient: .init(id: "p3", name: "林淑芬"))
  vm.state.isFirstAppear = false
  vm.state.api.loadRecord = .success
  return NavigationStack { PatientRecordView(viewModel: vm) }
}

#Preview("Load failed") {
  let vm = PatientRecordViewModel(client: .preview, patient: .init(id: "p4", name: "張文華"))
  vm.state.isFirstAppear = false
  vm.state.api.loadRecord = .error(message: "Can't reach the server. Check the address and your connection.")
  return NavigationStack { PatientRecordView(viewModel: vm) }
}
#endif
