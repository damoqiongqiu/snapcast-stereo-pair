import SwiftUI

struct SetupSidebar: View {
    let flow: SetupFlowState
    let select: (SetupStep) -> Void
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.green)
                .padding(.bottom, 16)
                .accessibilityHidden(true)

            ForEach(SetupStep.allCases) { step in
                Button {
                    select(step)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: marker(for: step))
                            .foregroundStyle(markerColor(for: step))
                            .frame(width: 18)
                        Text(verbatim: language.text(step.titleKey))
                            .foregroundStyle(step == flow.currentStep ? Theme.text : Theme.muted)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(
                        step == flow.currentStep
                            ? Theme.raised
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(step != flow.currentStep && !flow.completed.contains(step))
            }
            Spacer()
        }
        .padding(20)
        .background(Theme.surface)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.separator).frame(width: 1)
        }
    }

    private func marker(for step: SetupStep) -> String {
        if flow.completed.contains(step) {
            return "checkmark.circle.fill"
        }
        return step == flow.currentStep ? "circle.inset.filled" : "circle"
    }

    private func markerColor(for step: SetupStep) -> Color {
        if flow.completed.contains(step) {
            return Theme.green
        }
        return step == flow.currentStep ? Theme.blue : Theme.muted
    }
}
