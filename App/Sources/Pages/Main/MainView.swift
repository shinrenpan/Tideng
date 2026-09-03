import SwiftUI

// MARK: - Display Helpers

private extension MainViewModel.MenuItem {

  var title: String {
    switch self {
    case .patients: "病人"
    case .tasks: "今日待辦"
    case .vitals: "生命徵象"
    }
  }

  var symbolName: String {
    switch self {
    case .patients: "person.2.fill"
    case .tasks: "checklist"
    case .vitals: "waveform.path.ecg"
    }
  }
}

// MARK: - MainView

struct MainView: View {

  let viewModel: MainViewModel
  /// 側邊欄容器本來就得認識它要嵌入的東西——這是 split view 無法迴避的耦合。
  /// 換成 push 導航時，這個依賴會回到 HostController 的 handleRouter 裡。
  let patientListViewModel: PatientListViewModel

  var body: some View {
    NavigationSplitView {
      SidebarSection(
        items: viewModel.state.menuItems,
        selection: viewModel.state.selection,
        serverHost: viewModel.state.serverHost,
        practitionerReference: viewModel.state.practitionerReference,
        send: handleSidebarAction
      )
    } detail: {
      detail()
    }
    .navigationSplitViewStyle(.balanced)
    .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  @ViewBuilder private func detail() -> some View {
    switch viewModel.state.selection {
    case .patients:
      NavigationStack {
        PatientListView(viewModel: patientListViewModel)
      }
    case .tasks, .vitals:
      ContentUnavailableView(
        "尚未實作",
        systemImage: "hammer",
        description: Text("這個 PoC 先做通登入與病人清單")
      )
    }
  }

  @MainActor private func handleSidebarAction(_ action: SidebarSection.Action) {
    switch action {
    case let .itemDidTap(item):
      Task { await viewModel.doAction(.view(.menuItemDidTap(item))) }
    case .signOutDidTap:
      Task { await viewModel.doAction(.view(.signOutDidTap)) }
    }
  }
}

// MARK: - Sidebar

private extension MainView {

  struct SidebarSection: View {

    enum Action: Sendable {
      case itemDidTap(MainViewModel.MenuItem)
      case signOutDidTap
    }

    let items: [MainViewModel.MenuItem]
    let selection: MainViewModel.MenuItem
    let serverHost: String
    let practitionerReference: String?
    let send: @MainActor (Action) -> Void

    var body: some View {
      VStack(spacing: 0) {
        List {
          ForEach(items) { item in
            SidebarRow(
              item: item,
              isSelected: item == selection,
              onTap: { send(.itemDidTap(item)) }
            )
          }
        }
        .listStyle(.sidebar)

        Divider()

        SidebarFooter(
          serverHost: serverHost,
          practitionerReference: practitionerReference,
          onSignOut: { send(.signOutDidTap) }
        )
      }
      .navigationTitle("提燈")
    }
  }

  struct SidebarRow: View {

    let item: MainViewModel.MenuItem
    let isSelected: Bool
    let onTap: @MainActor () -> Void

    var body: some View {
      Button(action: onTap) {
        HStack(spacing: 12) {
          Image(systemName: item.symbolName)
            .frame(width: 22)
          Text(item.title)
          Spacer()
          if !item.isAvailable {
            Text("待實作")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(item.isAvailable ? Color.primary : Color.secondary)
      .listRowBackground(
        isSelected ? Color.accentColor.opacity(0.15) : Color.clear
      )
      .disabled(!item.isAvailable)
    }
  }

  struct SidebarFooter: View {

    let serverHost: String
    let practitionerReference: String?
    let onSignOut: @MainActor () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Label(serverHost, systemImage: "server.rack")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

          if let practitionerReference {
            Label(practitionerReference, systemImage: "person.badge.key")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Button("登出", systemImage: "rectangle.portrait.and.arrow.right", action: onSignOut)
          .font(.caption)
          .buttonStyle(.plain)
          .foregroundStyle(.red)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
  }
}
