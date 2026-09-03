import SwiftUI

// MARK: - ServerSetupView

struct ServerSetupView: View {

  let viewModel: ServerSetupViewModel

  var body: some View {
    @Bindable var bVM = viewModel

    ZStack {
      Color(.systemGroupedBackground)
        .ignoresSafeArea()

      ScrollView {
        VStack(spacing: 32) {
          header()

          FormSection(
            baseURL: $bVM.state.baseURLText,
            clientID: $bVM.state.clientIDText,
            isAdvancedExpanded: $bVM.state.isAdvancedExpanded,
            presets: viewModel.state.presets,
            canSignIn: viewModel.state.canSignIn,
            status: viewModel.state.api.signIn,
            send: handleFormAction
          )
        }
        .frame(maxWidth: 560)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
      }
    }
  }

  @ViewBuilder private func header() -> some View {
    VStack(spacing: 10) {
      Image(systemName: "lightbulb.fill")
        .font(.system(size: 40))
        .foregroundStyle(.tint)

      Text("Tideng")
        .font(.largeTitle.weight(.semibold))

      Text("Connect to any SMART on FHIR server")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  @MainActor private func handleFormAction(_ action: FormSection.Action) {
    switch action {
    case let .presetDidTap(id):
      Task { await viewModel.doAction(.view(.presetDidTap(id: id))) }
    case .signInDidTap:
      Task { await viewModel.doAction(.view(.signInDidTap)) }
    }
  }
}

// MARK: - Form

private extension ServerSetupView {

  struct FormSection: View {

    enum Action: Sendable {
      case presetDidTap(id: String)
      case signInDidTap
    }

    @Binding var baseURL: String
    @Binding var clientID: String
    @Binding var isAdvancedExpanded: Bool

    let presets: [ServerSetupViewModel.ServerPreset]
    let canSignIn: Bool
    let status: ServerSetupViewModel.Status
    let send: @MainActor (Action) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text("FHIR server address")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)

          TextField("https://example.org/fhir", text: $baseURL)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .font(.body.monospaced())
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
            .onSubmit { send(.signInDidTap) }
        }

        FormPresets(presets: presets) { id in
          send(.presetDidTap(id: id))
        }

        DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Client ID")
              .font(.footnote.weight(.medium))
              .foregroundStyle(.secondary)

            TextField("client_id", text: $clientID)
              .textFieldStyle(.plain)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .font(.body.monospaced())
              .padding(12)
              .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
          }
          .padding(.top, 12)
        }
        .font(.subheadline)
        .tint(.secondary)

        if case let .error(message) = status {
          Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(.vertical, 4)
        }

        Button {
          send(.signInDidTap)
        } label: {
          HStack(spacing: 8) {
            if status == .loading {
              ProgressView()
                .controlSize(.small)
                .tint(.white)
            }
            Text(status == .loading ? "Connecting…" : "Sign In")
              .font(.body.weight(.semibold))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSignIn)
      }
      .padding(24)
      .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: .rect(cornerRadius: 16))
    }
  }

  struct FormPresets: View {

    let presets: [ServerSetupViewModel.ServerPreset]
    let onSelect: @MainActor (String) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Quick fill")
          .font(.footnote.weight(.medium))
          .foregroundStyle(.secondary)

        ForEach(presets) { preset in
          Button {
            onSelect(preset.id)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                  .font(.subheadline.weight(.medium))
                Text(preset.note)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "arrow.up.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("Initial") {
  ServerSetupView(viewModel: ServerSetupViewModel())
}

#Preview("Sign-in failed") {
  let vm = ServerSetupViewModel()
  vm.state.baseURLText = "http://localhost:8090/v/r4/fhir"
  vm.state.api.signIn = .error(message: "This server doesn't support standalone sign-in")
  return ServerSetupView(viewModel: vm)
}
#endif
