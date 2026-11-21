import StereoPairCore
import SwiftUI

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: language.text("app.title")).font(.title2.bold())
                    Text(verbatim: language.format(
                        "app.subtitleFormat",
                        modeText(model.snapshot?.mode)
                    ))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Picker(language.text("language.label"), selection: $language.preference) {
                    ForEach(LanguagePreference.allCases, id: \.rawValue) { preference in
                        Text(verbatim: language.label(for: preference)).tag(preference)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .accessibilityLabel(language.text("accessibility.languagePicker"))

                Text(verbatim: healthText(model.snapshot?.health))
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(model.healthy ? Theme.green.opacity(0.18) : Theme.amber.opacity(0.18))
                    .foregroundStyle(model.healthy ? Theme.green : Theme.amber)
                    .clipShape(Capsule())
                    .accessibilityLabel(language.format(
                        "accessibility.connectionFormat",
                        language.text("status.control"),
                        healthText(model.snapshot?.health)
                    ))
            }

            Picker(language.text("mode.label"), selection: Binding(
                get: { model.isSnapcast ? AudioMode.snapcast : .system },
                set: { mode in Task { await model.setMode(mode) } }
            )) {
                Text(verbatim: language.text("mode.snapcast")).tag(AudioMode.snapcast)
                Text(verbatim: language.text("mode.system")).tag(AudioMode.system)
            }
            .pickerStyle(.segmented)
            .disabled(model.isWorking)
            .accessibilityLabel(language.text("accessibility.modePicker"))

            HStack(spacing: 14) {
                ChannelStrip(
                    title: language.text("channel.left"),
                    channel: model.left,
                    model: model
                )
                ChannelStrip(
                    title: language.text("channel.right"),
                    channel: model.right,
                    model: model
                )
            }

            MasterControl(model: model)
            StatusBus(model: model)

            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .frame(minWidth: 780, minHeight: 560)
    }

    private func modeText(_ mode: AudioMode?) -> String {
        switch mode {
        case .snapcast:
            return language.text("mode.snapcast")
        case .system:
            return language.text("mode.system")
        case .transitioning:
            return language.text("mode.transitioning")
        case nil:
            return language.text("mode.starting")
        }
    }

    private func healthText(_ health: HealthLevel?) -> String {
        switch health {
        case .healthy:
            return language.text("health.healthy")
        case .degraded:
            return language.text("health.degraded")
        case .failed:
            return language.text("health.failed")
        case .disabled:
            return language.text("health.disabled")
        case nil:
            return language.text("health.attention")
        }
    }
}

private struct ChannelStrip: View {
    let title: String
    let channel: ChannelStatus?
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(channel?.connected == true ? Theme.green : Theme.red).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(verbatim: "\(title) · \(channel?.clientId ?? language.text("channel.unavailable"))")
                    .font(.headline)
                    .accessibilityLabel(language.format(
                        "accessibility.connectionFormat",
                        title,
                        channel?.connected == true
                            ? language.text("status.connected")
                            : language.text("status.disconnected")
                    ))
                Spacer()
                Text(verbatim: channel?.streamId ?? "—").font(.caption).foregroundStyle(Theme.muted)
            }
            ChannelWaveform(channel: channel)
                .padding(.horizontal, 2)
            Slider(
                value: Binding(
                    get: { Double(channel?.volume ?? 0) },
                    set: { value in
                        if let channel { Task { await model.setVolume(channel, percent: Int(value)) } }
                    }
                ),
                in: 0...100
            )
            .accessibilityLabel(language.format("accessibility.volumeFormat", title))
            .accessibilityValue(language.format("channel.volumeFormat", channel?.volume ?? 0))
            HStack {
                Text(verbatim: language.format("channel.volumeFormat", channel?.volume ?? 0))
                Spacer()
                Toggle(language.text("mute.label"), isOn: Binding(
                    get: { channel?.muted ?? false },
                    set: { value in
                        if let channel { Task { await model.setMute(channel, muted: value) } }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(language.format("accessibility.muteFormat", title))
            }
            .font(.caption).foregroundStyle(Theme.muted)
            Stepper(
                language.format("latency.labelFormat", channel?.latencyMs ?? 0),
                value: Binding(
                    get: { channel?.latencyMs ?? 0 },
                    set: { value in
                        if let channel { Task { await model.setLatency(channel, milliseconds: value) } }
                    }
                ),
                in: 0...500
            )
            .font(.caption)
            .accessibilityLabel(language.format("accessibility.latencyFormat", title))
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator))
    }

}

private struct MasterControl: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: language.text("volume.master").uppercased())
                    .font(.caption2.bold()).foregroundStyle(Theme.muted)
                Text(verbatim: "\(model.masterVolume)%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Slider(
                value: Binding(
                    get: { Double(model.masterVolume) },
                    set: { value in Task { await model.setMaster(Int(value)) } }
                ),
                in: 0...100
            )
            .accessibilityLabel(language.text("accessibility.masterVolume"))
            .accessibilityValue("\(model.masterVolume)%")
        }
        .padding(14)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatusBus: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        HStack(spacing: 0) {
            zone(language.text("status.control"), items: [
                (language.text("service.snapserver"), isRunning("server"))
            ])
            zone(language.text("status.audioPath"), items: [
                (language.text("service.splitter"), isRunning("splitter")),
                (
                    language.text("service.clients"),
                    model.left?.connected == true && model.right?.connected == true
                )
            ])
            zone(language.text("status.routing"), items: [
                (language.text("service.routing"), model.snapshot?.issues.isEmpty == true)
            ])
            zone(language.text("status.recovery"), items: [
                (language.text("service.wakeRecovery"), isRunning("wake"))
            ])
        }
        .padding(.vertical, 9)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator))
    }

    private func zone(_ title: String, items: [(String, Bool?)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Circle().fill(item.1 == true ? Theme.green : item.1 == false ? Theme.red : Theme.muted)
                        .frame(width: 6, height: 6)
                        .shadow(color: item.1 == true ? Theme.green.opacity(0.6) : .clear, radius: 4)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(item.0) · \(stateText(item.1))")
                        .font(.system(size: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.separator).frame(width: 1) }
    }

    private func isRunning(_ labelFragment: String) -> Bool? {
        guard let state = model.snapshot?.services
            .first(where: { $0.id.contains(labelFragment) })?.state else {
            return nil
        }
        return state == .running
    }

    private func stateText(_ value: Bool?) -> String {
        switch value {
        case true:
            return language.text("status.healthy")
        case false:
            return language.text("status.failed")
        case nil:
            return language.text("health.unknown")
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(verbatim: menuStatus)
        Divider()
        Button(language.text("menu.openConsole")) { openWindow(id: "console") }
        Button(language.text("menu.enableSnapcast")) { Task { await model.setMode(.snapcast) } }
            .disabled(model.isWorking || model.isSnapcast)
        Button(language.text("menu.useSystem")) { Task { await model.setMode(.system) } }
            .disabled(model.isWorking || !model.isSnapcast)
        Divider()
        Text(verbatim: language.format("volume.totalFormat", model.masterVolume))
        Button(language.text("menu.quitGUI")) { NSApplication.shared.terminate(nil) }
    }

    private var menuStatus: String {
        guard model.isSnapcast else {
            return language.text("menu.systemMode")
        }
        return language.format(
            "menu.statusSnapcastFormat",
            language.text(model.healthy ? "status.healthy" : "status.warning")
        )
    }
}
