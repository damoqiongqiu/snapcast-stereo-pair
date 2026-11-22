import StereoPairCore
import SwiftUI

struct StatusBus: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        let allZones = zones

        HStack(spacing: 0) {
            ForEach(Array(allZones.enumerated()), id: \.element.id) { index, zone in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: zone.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    ForEach(zone.rows) { row in
                        ServiceLED(
                            appearance: ServiceLEDAppearance.resolve(
                                state: row.state,
                                freshActivity: row.freshActivity
                            ),
                            label: row.label,
                            statusText: language.text(
                                ServiceLEDAppearance.resolve(
                                    state: row.state,
                                    freshActivity: row.freshActivity
                                ).labelKey
                            )
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .overlay(alignment: .trailing) {
                    if StatusBusLayout.showsTrailingDivider(
                        after: index,
                        zoneCount: allZones.count
                    ) {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(width: 1)
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text("status.busLabel"))
    }

    private var zones: [Zone] {
        [
            Zone(
                id: "control",
                title: language.text("status.control"),
                rows: [
                    row(
                        id: "agent",
                        labelKey: "service.agent",
                        state: model.connectionState == .connected ? .running : .failed
                    ),
                    serviceRow(id: "com.snapcast.server", labelKey: "service.snapserver")
                ]
            ),
            Zone(
                id: "audio",
                title: language.text("status.audioPath"),
                rows: [
                    serviceRow(id: "com.snapcast.splitter", labelKey: "service.splitter"),
                    row(
                        id: "left-client",
                        labelKey: "channel.left",
                        state: model.left?.connected == true ? .running : .inactive
                    ),
                    row(
                        id: "right-client",
                        labelKey: "channel.right",
                        state: model.right?.connected == true ? .running : .inactive
                    )
                ]
            ),
            Zone(
                id: "routing",
                title: language.text("status.routing"),
                rows: [
                    row(
                        id: "left-route",
                        labelKey: "service.leftRoute",
                        state: routeState(streamId: "LeftAudio")
                    ),
                    row(
                        id: "right-route",
                        labelKey: "service.rightRoute",
                        state: routeState(streamId: "RightAudio")
                    ),
                    row(
                        id: "format",
                        labelKey: "service.format",
                        state: model.snapshot?.issues.isEmpty == true ? .running : .inactive
                    )
                ]
            ),
            Zone(
                id: "recovery",
                title: language.text("status.recovery"),
                rows: [
                    serviceRow(
                        id: "com.snapcast.pairing",
                        labelKey: "service.pairing"
                    ),
                    serviceRow(
                        id: "com.snapcast.wake-recovery",
                        labelKey: "service.wakeRecovery"
                    )
                ]
            )
        ]
    }

    private func row(
        id: String,
        labelKey: String,
        state: ServiceState?
    ) -> Row {
        Row(id: id, label: language.text(labelKey), state: state, freshActivity: false)
    }

    private func serviceRow(id: String, labelKey: String) -> Row {
        let service = model.snapshot?.services.first { $0.id == id }
        return Row(
            id: id,
            label: language.text(labelKey),
            state: RecoveryHealthPresentation.effectiveState(for: service),
            freshActivity: (service?.lastSuccessAgeSeconds ?? .infinity) <= 2
        )
    }

    private func routeState(streamId: String) -> ServiceState? {
        guard let stream = model.snapshot?.streams.first(where: { $0.id == streamId }),
              let clientId = stream.clientIds.first else {
            return model.snapshot == nil ? nil : .inactive
        }
        return model.snapshot?.channels.contains {
            $0.clientId == clientId && $0.streamId == streamId && $0.connected
        } == true ? .running : .failed
    }
}

enum StatusBusLayout {
    static func showsTrailingDivider(after index: Int, zoneCount: Int) -> Bool {
        index >= 0 && index < zoneCount - 1
    }
}

private struct Zone: Identifiable {
    let id: String
    let title: String
    let rows: [Row]
}

private struct Row: Identifiable {
    let id: String
    let label: String
    let state: ServiceState?
    let freshActivity: Bool
}
