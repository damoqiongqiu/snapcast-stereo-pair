import StereoPairCore
import SwiftUI

struct SetupFlowView: View {
    @ObservedObject var setup: SetupViewModel
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        HStack(spacing: 0) {
            SetupSidebar(flow: setup.flow) { step in
                setup.showStep(step)
            }
            .frame(width: 220)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: language.text("setup.title"))
                        .font(.title.bold())
                    Text(verbatim: language.text("setup.subtitle"))
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }

                Divider().overlay(Theme.separator)

                currentStep
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if let error = setup.flow.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                }

                HStack {
                    Button(language.text("setup.refreshChecks")) {
                        Task { await setup.refreshChecks() }
                    }
                    .disabled(setup.isRefreshing || setup.flow.pendingAction != nil)
                    Spacer()
                    Button(language.text("setup.skip")) {
                        setup.skipSetup()
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(28)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .frame(
            minWidth: MainWindowMetrics.minimumSize.width,
            minHeight: MainWindowMetrics.minimumSize.height
        )
        .task { await setup.start() }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch setup.flow.currentStep {
        case .welcome:
            welcomeStep
        case .dependencies:
            dependenciesStep
        case .localRuntime:
            LocalSetupStep(setup: setup)
        case .remoteMac:
            RemoteSetupStep(setup: setup)
        case .verification:
            VerificationStep(setup: setup, model: model) {
                Task {
                    await notifications.markSetupComplete()
                }
            }
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepIcon("hifispeaker.2.fill")
            Text(verbatim: language.text("setup.welcomeTitle"))
                .font(.title2.bold())
            Text(verbatim: language.text("setup.welcomeBody"))
                .font(.body)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                welcomePoint("speaker.wave.2.fill", "setup.welcomePointAudio")
                welcomePoint("lock.shield.fill", "setup.welcomePointPrivacy")
                welcomePoint("arrow.triangle.2.circlepath", "setup.welcomePointRecovery")
            }

            Spacer()
            Button(language.text("setup.continue")) {
                setup.completeWelcome()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var dependenciesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: language.text("setup.dependencies.title"))
                .font(.title2.bold())
            Text(verbatim: language.text("setup.dependencies.body"))
                .foregroundStyle(Theme.muted)

            VStack(spacing: 0) {
                ForEach(setup.checks) { check in
                    HStack(spacing: 12) {
                        ServiceLED(
                            appearance: dependencyAppearance(check),
                            label: language.text("setup.dependency.\(check.dependency.rawValue)"),
                            statusText: language.text("setup.status.\(check.status.rawValue)")
                        )
                        Spacer()
                        if let version = check.version {
                            Text(verbatim: version)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 10)
                    if check.id != setup.checks.last?.id {
                        Divider().overlay(Theme.separator)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let remediation = setup.checks.first(where: {
                $0.dependency != .runtime && $0.status != .ready
            })?.remediationKey {
                Text(verbatim: language.text(remediation))
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
            }

            Spacer()
            Button(language.text("setup.continue")) {
                setup.completeDependencies()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!setup.externalDependenciesReady)
        }
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(Theme.green)
            .frame(width: 58, height: 58)
            .background(Theme.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }

    private func welcomePoint(_ icon: String, _ key: String) -> some View {
        Label {
            Text(verbatim: language.text(key))
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.blue)
        }
    }

    private func dependencyAppearance(_ check: SetupCheck) -> ServiceLEDAppearance {
        let state: ServiceState = switch check.status {
        case .ready:
            .running
        case .missing, .outdated:
            .inactive
        case .malformed:
            .failed
        }
        return ServiceLEDAppearance.resolve(state: state, freshActivity: false)
    }
}
