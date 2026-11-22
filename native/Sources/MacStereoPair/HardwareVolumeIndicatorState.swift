import Foundation
import StereoPairCore

struct HardwareVolumeIndicatorState: Equatable {
    enum Tone: Equatable {
        case healthy
        case warning
        case unavailable
        case stale
    }

    static let staleAfter: TimeInterval = 60

    let tone: Tone
    let valueText: String
    let labelKey: String

    static func make(
        status: HardwareVolumeStatus?,
        now: Date = Date()
    ) -> HardwareVolumeIndicatorState {
        guard let status, let volume = status.volumePercent else {
            return HardwareVolumeIndicatorState(
                tone: .unavailable,
                valueText: "—",
                labelKey: "systemVolume.unavailable"
            )
        }

        let valueText = "\(Int(volume.rounded()))%"
        guard let checkedAt = status.checkedAt else {
            return HardwareVolumeIndicatorState(
                tone: .unavailable,
                valueText: valueText,
                labelKey: "systemVolume.unavailable"
            )
        }
        if now.timeIntervalSince(checkedAt) > staleAfter {
            return HardwareVolumeIndicatorState(
                tone: .stale,
                valueText: valueText,
                labelKey: "systemVolume.stale"
            )
        }
        if volume >= 100 {
            return HardwareVolumeIndicatorState(
                tone: .healthy,
                valueText: valueText,
                labelKey: "systemVolume.normal"
            )
        }
        return HardwareVolumeIndicatorState(
            tone: .warning,
            valueText: valueText,
            labelKey: "systemVolume.low"
        )
    }
}
