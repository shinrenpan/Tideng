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

private extension MainViewModel.PatientSlice {

  /// 切片名稱一律陳述事實。「超出參考值」而不是「異常」——後者是判讀。
  var title: String {
    switch self {
    case .all: String(localized: "All Patients")
    case .seenToday: String(localized: "Seen Today")
    case .outOfRange: String(localized: "Outside Reference Range")
    case .onMedication: String(localized: "On Medication")
    }
  }

  /// 說明這個切片涵蓋的範圍。時間窗要講出來，否則數字沒有意義。
  var caption: String? {
    switch self {
    case .all: nil
    case .seenToday: nil
    case .outOfRange: String(localized: "Last 24 hours")
    case .onMedication: nil
    }
  }

  var symbolName: String {
    switch self {
    case .all: "person.2"
    case .seenToday: "calendar"
    case .outOfRange: "arrow.up.arrow.down"
    case .onMedication: "pills"
    }
  }
}

private extension MainViewModel.SliceCount {

  /// 下限值必須看得出來是下限，否則會被當成總數。
  var displayText: String {
    switch self {
    case let .exact(value): value.formatted()
    case let .atLeast(value): String(localized: "\(value)+")
    }
  }
}

// MARK: - MainView

struct MainView: View {

  let viewModel: MainViewModel
  /// 四個切片各自的清單 ViewModel，由 HostController 建立並持有——
  /// View 不自建，也不快取。
  let patientLists: [MainViewModel.PatientSlice: PatientListViewModel]

  var body: some View {
    @Bindable var bVM = viewModel

    NavigationSplitView {
      SidebarSection(
        practitioner: viewModel.state.practitioner,
        categories: MainViewModel.Category.allCases,
        selection: .patients,
        serverHost: viewModel.state.serverHost,
        send: handleSidebarAction
      )
    } detail: {
      NavigationStack {
        SliceSection(cards: viewModel.state.sliceCards, send: handleSliceAction)
          .navigationTitle(MainViewModel.Category.patients.title)
          .navigationDestination(item: $bVM.state.presentedSlice) { slice in
            if let listViewModel = patientLists[slice] {
              PatientListView(viewModel: listViewModel)
            }
          }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .task { await viewModel.doAction(.view(.isFirstAppear)) }
  }

  @MainActor private func handleSidebarAction(_ action: SidebarSection.Action) {
    switch action {
    case .categoryDidTap:
      // 目前只有一個大分類，選取不改變任何東西。
      break
    case .signOutDidTap:
      Task { await viewModel.doAction(.view(.signOutDidTap)) }
    }
  }

  @MainActor private func handleSliceAction(_ action: SliceSection.Action) {
    switch action {
    case let .cardDidTap(slice):
      Task { await viewModel.doAction(.view(.sliceDidTap(slice))) }
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

    let practitioner: MainViewModel.PractitionerIdentity?
    let categories: [MainViewModel.Category]
    let selection: MainViewModel.Category
    let serverHost: String
    let send: @MainActor (Action) -> Void

    var body: some View {
      VStack(spacing: 0) {
        SidebarHeader(practitioner: practitioner)

        Divider()

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

        SidebarFooter(serverHost: serverHost, onSignOut: { send(.signOutDidTap) })
      }
      .navigationTitle("Tideng")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  struct SidebarHeader: View {

    let practitioner: MainViewModel.PractitionerIdentity?

    var body: some View {
      HStack(spacing: 12) {
        Image(systemName: "person.crop.circle.fill")
          .font(.system(size: 34))
          .foregroundStyle(.tint)

        VStack(alignment: .leading, spacing: 2) {
          Text(practitioner?.displayName ?? "")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)

          // 職位取不到就整行消失，不留空白佔位。
          if let role = practitioner?.role {
            Text(role)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
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
    let onSignOut: @MainActor () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        Label(serverHost, systemImage: "server.rack")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

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

// MARK: - Slice grid

private extension MainView {

  struct SliceSection: View {

    enum Action: Sendable {
      case cardDidTap(MainViewModel.PatientSlice)
    }

    let cards: [MainViewModel.SliceCard]
    let send: @MainActor (Action) -> Void

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 16)]

    var body: some View {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(cards) { card in
            SliceTile(card: card) { send(.cardDidTap(card.slice)) }
          }
        }
        .padding(20)
      }
      .background(Color(.systemGroupedBackground))
    }
  }

  struct SliceTile: View {

    let card: MainViewModel.SliceCard
    let onTap: @MainActor () -> Void

    var body: some View {
      Button(action: onTap) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Image(systemName: card.slice.symbolName)
              .font(.title3)
              .foregroundStyle(.tint)
            Spacer()
            count()
          }

          VStack(alignment: .leading, spacing: 2) {
            Text(card.slice.title)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)

            if let caption = card.slice.caption {
              Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
      }
      .buttonStyle(.plain)
    }

    /// 卡片先出現、數字後到——所以載入中也要佔住同一個位置，不讓版面跳動。
    @ViewBuilder private func count() -> some View {
      switch card.state.status {
      case .prepare, .loading:
        ProgressView()
          .controlSize(.small)

      case .success:
        Text(card.state.count?.displayText ?? "")
          .font(.title2.weight(.semibold))
          .monospacedDigit()
          .contentTransition(.numericText())

      case .unavailable:
        // 計數取不到不等於清單不能開，所以卡片仍可點。
        Image(systemName: "exclamationmark.triangle")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}
