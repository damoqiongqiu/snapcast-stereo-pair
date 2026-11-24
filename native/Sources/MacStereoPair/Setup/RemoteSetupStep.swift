import SwiftUI

struct RemoteSetupStep: View {
    @ObservedObject var setup: SetupViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: language.text("setup.remote.title"))
                .font(.title2.bold())
            Text(verbatim: language.text("setup.remote.body"))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                TextField(language.text("setup.remote.user"), text: $setup.remoteUser)
                    .textContentType(.username)
                TextField(language.text("setup.remote.host"), text: $setup.remoteHost)
            }
            .textFieldStyle(.roundedBorder)
            .disabled(setup.flow.pendingAction != nil)

            if setup.flow.pendingAction != nil {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: language.text("setup.remote.waiting"))
                        .font(.caption)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.amber.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
            HStack {
                Button(language.text("setup.remote.openTerminal")) {
                    setup.beginRemoteSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(setup.remoteUser.isEmpty || setup.remoteHost.isEmpty)

                Button(language.text("setup.remote.completed")) {
                    setup.completeRemoteSetup()
                }
                .disabled(
                    setup.flow.pendingAction == nil ||
                        !setup.remoteConfigurationReady
                )
            }
        }
    }
}
