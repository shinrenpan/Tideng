import SwiftUI

// MARK: - Display Helpers

private extension PatientMedicationsViewModel.RequestStatus {

  /// 記錄的 status 的顯示文字。只換寫法，不改變它說的事。
  var label: String {
    switch self {
    case .active: String(localized: "Active")
    case .onHold: String(localized: "On hold")
    case .cancelled: String(localized: "Cancelled")
    case .completed: String(localized: "Completed")
    case .enteredInError: String(localized: "Entered in error")
    case .stopped: String(localized: "Stopped")
    case .draft: String(localized: "Draft")
    case .unknown: String(localized: "Unknown")
    case let .other(code): code
    }
  }
}

private extension PatientMedicationsViewModel.Dose {

  /// 一次的量。單位缺漏時只顯示數字——不從藥品名稱反推單位。
  var text: String {
    let amount = value.formatted(.number.precision(.fractionLength(0...2)))
    guard let unit, !unit.isEmpty else { return amount }
    return "\(amount) \(unit)"
  }
}

// MARK: - PatientMedicationsView

struct PatientMedicationsView: View {

  let viewModel: PatientMedicationsViewModel

  var body: some View {
    content()
      .navigationTitle(viewModel.state.patient.name)
      .navigationBarTitleDisplayMode(.inline)
      .refreshable { await viewModel.doAction(.view(.pullToRefresh)) }
      .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  // 先看有沒有內容、再看狀態：刷新失敗時不能把眼前的處方換成錯誤畫面。
  @ViewBuilder private func content() -> some View {
    if !viewModel.state.prescriptions.isEmpty {
      ListSection(prescriptions: viewModel.state.prescriptions)
    } else {
      switch viewModel.state.api.loadPrescriptions {
      case .prepare, .loading:
        ProgressView()

      case let .error(message):
        ContentUnavailableView {
          Label("Can't load prescriptions", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            Task { await viewModel.doAction(.view(.retryDidTap)) }
          }
        }

      case .success:
        ContentUnavailableView("No prescriptions recorded for this patient", systemImage: "pills")
      }
    }
  }
}

// MARK: - List

private extension PatientMedicationsView {

  /// 純展示，沒有互動——不需要 `enum Action`。
  struct ListSection: View {

    let prescriptions: [PatientMedicationsViewModel.Prescription]

    var body: some View {
      List(prescriptions) { prescription in
        Row(prescription: prescription)
      }
      .listStyle(.plain)
    }
  }

  struct Row: View {

    let prescription: PatientMedicationsViewModel.Prescription

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          if let medication = prescription.medication {
            Text(medication)
              .font(.body.weight(.medium))
          }
          Text(prescription.status.label)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
        }

        // 沒有 dosageInstruction 就不顯示劑量段，也不填補任何東西。
        if !prescription.dosages.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(prescription.dosages) { dosage in
              DosageRow(dosage: dosage)
            }
          }
        }

        if let requester = prescription.requester {
          // 解析不到姓名就顯示 reference 本身——它仍然指得出是誰。
          LabeledContent("Prescribed by", value: requester.name ?? requester.reference)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 6)
    }
  }

  /// 一段給藥指示。
  ///
  /// 本頁最重要的一段：記錄說了幾點就顯示幾點，記錄沒說就**明說它沒說**。
  /// 絕不把「一天三次」展開成 08:00／16:00／24:00——那三個時間點是機構的
  /// 給藥常規，不在這份記錄裡。
  struct DosageRow: View {

    let dosage: PatientMedicationsViewModel.DosageLine

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          if let dose = dosage.dose {
            Text(dose.text)
          }
          if let schedule = dosage.schedule {
            Text(schedule.text)
          }
        }
        .font(.subheadline)

        if let note = dosage.schedule?.unspecifiedTimesNote {
          Text(note)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("With prescriptions") {
  let vm = PatientMedicationsViewModel(client: .preview, patient: .init(id: "p1", name: "王志明"))
  vm.state.isFirstAppear = false
  vm.state.prescriptions = PatientMedicationsViewModel.Prescription.mocks
  vm.state.api.loadPrescriptions = .success
  return NavigationStack { PatientMedicationsView(viewModel: vm) }
}

#Preview("No prescriptions") {
  let vm = PatientMedicationsViewModel(client: .preview, patient: .init(id: "p2", name: "陳美玲"))
  vm.state.isFirstAppear = false
  vm.state.api.loadPrescriptions = .success
  return NavigationStack { PatientMedicationsView(viewModel: vm) }
}

#Preview("Load failed") {
  let vm = PatientMedicationsViewModel(client: .preview, patient: .init(id: "p3", name: "林淑芬"))
  vm.state.isFirstAppear = false
  vm.state.api.loadPrescriptions = .error(message: "Can't reach the server. Check the address and your connection.")
  return NavigationStack { PatientMedicationsView(viewModel: vm) }
}
#endif
