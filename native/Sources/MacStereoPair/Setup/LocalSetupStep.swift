import StereoPairCore
import SwiftUI

struct LocalSetupStep: View {
    @ObservedObject var setup: SetupViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: language.text("setup.local.title"))
                .font(.title2.bold())
            Text(verbatim: language.text("setup.local.body"))
                .foregroundStyle(Theme.muted)

            runtimeStatus

            if setup.flow.pendingAction == .installLocalRuntime {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: language.text("setup.local.waiting"))
                        .font(.caption)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.amber.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
            HStack {
                if runtimeReady {
                    Button(language.text("setup.continue")) {
                        setup.completeLocalRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(language.text("setup.openTerminal")) {
                        setup.beginLocalInstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(setup.flow.pendingAction != nil)
                }
            }
        }
    }

    private var runtimeReady: Bool {
        setup.checks.first(where: { $0.dependency == .runtime })?.status == .ready
    }

    private var runtimeStatus: some View {
        HStack(spacing: 12) {
            ServiceLED(
                appearance: ServiceLEDAppearance.resolve(
                    state: runtimeReady ? .running : .inactive,
                    freshActivity: false
                ),
                label: language.text("setup.dependency.runtime"),
                statusText: language.text(runtimeReady ? "setup.status.ready" : "setup.status.missing")
            )
            Spacer()
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
