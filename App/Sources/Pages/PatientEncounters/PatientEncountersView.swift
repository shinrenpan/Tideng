import SwiftUI

// MARK: - Display Helpers

private extension PatientEncountersViewModel.VisitStatus {

  /// 記錄的 status 的顯示文字。
  ///
  /// 只是把 FHIR 的碼換成看得懂的字，**不改變它說的事**。不認得的碼原樣顯示——
  /// 那個碼是記錄的一部分，換成「未知」會把資訊丟掉。
  var label: String {
    switch self {
    case .planned: String(localized: "Planned")
    case .arrived: String(localized: "Arrived")
    case .triaged: String(localized: "Triaged")
    case .inProgress: String(localized: "In progress")
    case .onleave: String(localized: "On leave")
    case .finished: String(localized: "Finished")
    case .cancelled: String(localized: "Cancelled")
    case .enteredInError: String(localized: "Entered in error")
    case .unknown: String(localized: "Unknown")
    case let .other(code): code
    }
  }
}

private extension Date {

  var encounterTimeText: String {
    formatted(date: .abbreviated, time: .shortened)
  }
}

// MARK: - PatientEncountersView

struct PatientEncountersView: View {

  let viewModel: PatientEncountersViewModel

  var body: some View {
    content()
      .navigationTitle(viewModel.state.patient.name)
      .navigationBarTitleDisplayMode(.inline)
      .refreshable { await viewModel.doAction(.view(.pullToRefresh)) }
      .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  // 先看有沒有內容、再看狀態：刷新失敗時不能把眼前的清單換成錯誤畫面。
  @ViewBuilder private func content() -> some View {
    if !viewModel.state.encounters.isEmpty {
      ListSection(encounters: viewModel.state.encounters)
    } else {
      switch viewModel.state.api.loadEncounters {
      case .prepare, .loading:
        ProgressView()

      case let .error(message):
        ContentUnavailableView {
          Label("Can't load visits", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        } actions: {
          Button("Try Again") {
            Task { await viewModel.doAction(.view(.retryDidTap)) }
          }
        }

      case .success:
        ContentUnavailableView("No visits recorded for this patient", systemImage: "calendar")
      }
    }
  }
}

// MARK: - List

private extension PatientEncountersView {

  /// 純展示，沒有互動——不需要 `enum Action`。
  struct ListSection: View {

    let encounters: [PatientEncountersViewModel.Encounter]

    var body: some View {
      List(encounters) { encounter in
        Row(encounter: encounter)
      }
      .listStyle(.plain)
    }
  }

  struct Row: View {

    let encounter: PatientEncountersViewModel.Encounter

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          Text(encounter.status.label)
            .font(.body.weight(.medium))
          if let classDisplay = encounter.classDisplay {
            Text(classDisplay)
              .font(.caption)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.quaternary, in: .capsule)
          }
        }

        PeriodLine(encounter: encounter)

        if !encounter.participants.isEmpty {
          ParticipantsLine(participants: encounter.participants)
        }
      }
      .padding(.vertical, 6)
    }
  }

  /// period 的三種形態各說各的話。
  ///
  /// 這是本頁最重要的一段：**沒有 `end` 時不填當下時間，也不留白**。留白會被讀成
  /// 「結束了但沒記」，填當下時間則是替記錄宣稱它沒說的事。
  struct PeriodLine: View {

    let encounter: PatientEncountersViewModel.Encounter

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        if let startedAt = encounter.startedAt {
          LabeledContent("Started", value: startedAt.encounterTimeText)
        }
        if let endedAt = encounter.endedAt {
          LabeledContent("Ended", value: endedAt.encounterTimeText)
        } else if encounter.hasOpenPeriod {
          LabeledContent("Ended", value: String(localized: "Not recorded — the period is still open"))
        }
        if encounter.hasNoPeriod {
          Text("This visit has no recorded time.")
        }
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }

  struct ParticipantsLine: View {

    let participants: [PatientEncountersViewModel.Participant]

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(participants) { participant in
          // 解析不到姓名就顯示 reference 本身——它仍然指得出是誰，比空白有用。
          LabeledContent("Practitioner", value: participant.name ?? participant.id)
        }
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("With visits") {
  let vm = PatientEncountersViewModel(client: .preview, patient: .init(id: "p1", name: "王志明"))
  vm.state.isFirstAppear = false
  vm.state.encounters = PatientEncountersViewModel.Encounter.mocks
  vm.state.api.loadEncounters = .success
  return NavigationStack { PatientEncountersView(viewModel: vm) }
}

#Preview("No visits") {
  let vm = PatientEncountersViewModel(client: .preview, patient: .init(id: "p2", name: "陳美玲"))
  vm.state.isFirstAppear = false
  vm.state.api.loadEncounters = .success
  return NavigationStack { PatientEncountersView(viewModel: vm) }
}

#Preview("Load failed") {
  let vm = PatientEncountersViewModel(client: .preview, patient: .init(id: "p3", name: "林淑芬"))
  vm.state.isFirstAppear = false
  vm.state.api.loadEncounters = .error(message: "Can't reach the server. Check the address and your connection.")
  return NavigationStack { PatientEncountersView(viewModel: vm) }
}
#endif
