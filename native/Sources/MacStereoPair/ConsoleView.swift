import StereoPairCore
import SwiftUI

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @EnvironmentObject private var notifications: NotificationManager
    @State private var showsAdvanced = false

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

                Button {
                    showsAdvanced = true
                } label: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(language.text("advanced.open"))
                .accessibilityLabel(language.text("advanced.open"))
                .keyboardShortcut(",", modifiers: [.command, .shift])

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

            if model.showsTransition {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(verbatim: language.text("transition.inProgress"))
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.amber.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

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
        .onChange(of: model.snapshot) { _, snapshot in
            guard let snapshot else { return }
            Task {
                await notifications.process(snapshot: snapshot, language: language)
            }
        }
        .sheet(isPresented: $showsAdvanced) {
            AdvancedView(model: model)
                .environmentObject(language)
        }
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
