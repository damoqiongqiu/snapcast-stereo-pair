import SwiftUI

struct VerificationStep: View {
    @ObservedObject var setup: SetupViewModel
    @ObservedObject var model: ConsoleViewModel
    let setupCompleted: () -> Void
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(verbatim: language.text("setup.verification.title"))
                .font(.title2.bold())
            Text(verbatim: language.text("setup.verification.body"))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 12) {
                verificationRow("setup.dependency.runtime", runtimeReady)
                verificationRow("service.leftRoute", leftReady)
                verificationRow("service.rightRoute", rightReady)
            }

            if let message = setup.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
            }

            Spacer()
            Button(language.text(setup.flow.isConsoleEnabled ? "setup.openConsole" : "setup.verification.verify")) {
                if setup.flow.isConsoleEnabled {
                    setupCompleted()
                } else {
                    Task {
                        await model.refresh()
                        setup.finishVerification(snapshot: model.snapshot)
                        if setup.flow.isConsoleEnabled {
                            setupCompleted()
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var runtimeReady: Bool {
        setup.checks.first(where: { $0.dependency == .runtime })?.status == .ready
    }

    private var leftReady: Bool {
        model.left?.connected == true && model.left?.streamId == "LeftAudio"
    }

    private var rightReady: Bool {
        model.right?.connected == true && model.right?.streamId == "RightAudio"
    }

    private func verificationRow(_ labelKey: String, _ ready: Bool) -> some View {
        ServiceLED(
            appearance: ServiceLEDAppearance.resolve(
                state: ready ? .running : .inactive,
                freshActivity: false
            ),
            label: language.text(labelKey),
            statusText: language.text(ready ? "setup.status.ready" : "setup.status.waiting")
        )
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
