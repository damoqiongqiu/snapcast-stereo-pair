import StereoPairCore
import SwiftUI

enum LEDTone: Equatable {
    case green
    case amber
    case red
    case gray
}

enum LEDMotion: Equatable {
    case steady
    case pulse
}

struct ServiceLEDAppearance: Equatable {
    let tone: LEDTone
    let motion: LEDMotion
    let labelKey: String

    static func resolve(
        state: ServiceState?,
        freshActivity: Bool,
        reduceMotion: Bool = false
    ) -> ServiceLEDAppearance {
        switch state {
        case .running:
            return ServiceLEDAppearance(
                tone: .green,
                motion: freshActivity && !reduceMotion ? .pulse : .steady,
                labelKey: "status.healthy"
            )
        case .failed, .crashLoop:
            return ServiceLEDAppearance(tone: .red, motion: .steady, labelKey: "status.failed")
        case .disabled:
            return ServiceLEDAppearance(tone: .gray, motion: .steady, labelKey: "status.disabled")
        case .inactive, .unknown, nil:
            return ServiceLEDAppearance(tone: .amber, motion: .steady, labelKey: "status.warning")
        }
    }

    var color: Color {
        switch tone {
        case .green:
            return Theme.green
        case .amber:
            return Theme.amber
        case .red:
            return Theme.red
        case .gray:
            return Theme.muted.opacity(0.55)
        }
    }
}

struct ServiceLED: View {
    let appearance: ServiceLEDAppearance
    let label: String
    let statusText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(appearance.color.opacity(0.48), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .scaleEffect(isPulsing ? 1.35 : 0.9)
                    .opacity(isPulsing ? 0.12 : 0.72)
                Circle()
                    .fill(appearance.color)
                    .frame(width: 7, height: 7)
                    .shadow(color: appearance.color.opacity(0.72), radius: 4)
            }
            .accessibilityHidden(true)
            Text(verbatim: "\(label) · \(statusText)")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(statusText)
        .onAppear(perform: updatePulse)
        .onChange(of: appearance) { _ in updatePulse() }
        .onChange(of: reduceMotion) { _ in updatePulse() }
    }

    private func updatePulse() {
        guard appearance.motion == .pulse, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.2)) {
                isPulsing = false
            }
            return
        }
        isPulsing = false
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}
