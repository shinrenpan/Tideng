import SwiftUI

// MARK: - Display Helpers

private extension MainViewModel.Category {

  var title: String {
    switch self {
    case .patients: String(localized: "Patients")
    }
  }

  var symbolName: String {
    switch self {
    case .patients: "person.2.fill"
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
        categories: MainViewModel.Category.allCases,
        selection: .patients,
        serverHost: viewModel.state.serverHost,
        practitioner: viewModel.state.practitioner,
        send: handleSidebarAction
      )
    } detail: {
      detail()
    }
    .navigationSplitViewStyle(.balanced)
    .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  @ViewBuilder private func detail() -> some View {
    NavigationStack {
      PatientListView(viewModel: patientListViewModel)
    }
  }

  @MainActor private func handleSidebarAction(_ action: SidebarSection.Action) {
    switch action {
    case .categoryDidTap:
      break
    case .signOutDidTap:
      Task { await viewModel.doAction(.view(.signOutDidTap)) }
    }
  }
}

// MARK: - Sidebar

private extension MainView {

  struct SidebarSection: View {

    enum Action: Sendable {
      case categoryDidTap(MainViewModel.Category)
      case signOutDidTap
    }

    let categories: [MainViewModel.Category]
    let selection: MainViewModel.Category
    let serverHost: String
    let practitioner: MainViewModel.PractitionerIdentity?
    let send: @MainActor (Action) -> Void

    var body: some View {
      VStack(spacing: 0) {
        List {
          ForEach(categories) { category in
            SidebarRow(
              category: category,
              isSelected: category == selection,
              onTap: { send(.categoryDidTap(category)) }
            )
          }
        }
        .listStyle(.sidebar)

        Divider()

        SidebarFooter(
          serverHost: serverHost,
          practitionerReference: practitioner?.reference,
          onSignOut: { send(.signOutDidTap) }
        )
      }
      .navigationTitle("Tideng")
    }
  }

  struct SidebarRow: View {

    let category: MainViewModel.Category
    let isSelected: Bool
    let onTap: @MainActor () -> Void

    var body: some View {
      Button(action: onTap) {
        HStack(spacing: 12) {
          Image(systemName: category.symbolName)
            .frame(width: 22)
          Text(category.title)
          Spacer()
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
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

        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", action: onSignOut)
          .font(.caption)
          .buttonStyle(.plain)
          .foregroundStyle(.red)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
  }
}
