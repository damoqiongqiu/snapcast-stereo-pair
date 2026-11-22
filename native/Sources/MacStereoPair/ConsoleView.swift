import StereoPairCore
import SwiftUI

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @EnvironmentObject private var notifications: NotificationManager
    @State private var showsAdvanced = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                consoleContent
                    .frame(maxWidth: MainWindowMetrics.contentMaxWidth)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: geometry.size.height,
                        alignment: .center
                    )
            }
            .scrollIndicators(.automatic)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .frame(
            minWidth: MainWindowMetrics.minimumSize.width,
            minHeight: MainWindowMetrics.minimumSize.height
        )
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

    private var consoleContent: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: language.text("app.title")).font(.title2.bold())
                    Text(verbatim: language.format(
                        "app.subtitleFormat",
                        modeText(model.snapshot?.mode)
                    ))
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 24)

                HStack(spacing: 8) {
                    LanguageMenu()

                    Button {
                        showsAdvanced = true
                    } label: {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .frame(width: 30, height: 30)
                            .background(Theme.raised)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(language.text("advanced.open"))
                    .accessibilityLabel(language.text("advanced.open"))
                    .keyboardShortcut(",", modifiers: [.command, .shift])

                    Text(verbatim: healthText(model.snapshot?.health))
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            model.healthy
                                ? Theme.green.opacity(0.18)
                                : Theme.amber.opacity(0.18)
                        )
                        .foregroundStyle(model.healthy ? Theme.green : Theme.amber)
                        .clipShape(Capsule())
                        .accessibilityLabel(language.format(
                            "accessibility.connectionFormat",
                            language.text("status.control"),
                            healthText(model.snapshot?.health)
                        ))
                }
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
                    hardwareVolume: model.hardwareVolume(side: "left"),
                    model: model
                )
                ChannelStrip(
                    title: language.text("channel.right"),
                    channel: model.right,
                    hardwareVolume: model.hardwareVolume(side: "right"),
                    model: model
                )
            }

            HardwareVolumeLegend(model: model)
            MasterControl(model: model)
            StatusBus(model: model)

            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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

private struct LanguageMenu: View {
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        Menu {
            ForEach(LanguagePreference.allCases, id: \.rawValue) { preference in
                Button {
                    language.preference = preference
                } label: {
                    if language.preference == preference {
                        Label(language.label(for: preference), systemImage: "checkmark")
                    } else {
                        Text(verbatim: language.label(for: preference))
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Theme.raised)
                .clipShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(language.text("language.label"))
        .accessibilityLabel(language.text("accessibility.languagePicker"))
    }
}

private struct ChannelStrip: View {
    let title: String
    let channel: ChannelStatus?
    let hardwareVolume: HardwareVolumeStatus?
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @State private var displayedVolume: Double?

    private var publishedVolume: Double {
        Double(channel?.volume ?? 0)
    }

    private var effectiveVolume: Double {
        displayedVolume ?? publishedVolume
    }

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
            HardwareVolumeIndicator(
                title: title,
                status: hardwareVolume
            )
            HStack {
                Text(verbatim: language.text("volume.snapcast").uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(verbatim: language.format(
                    "channel.volumeFormat",
                    Int(effectiveVolume.rounded())
                ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .combine)
            VolumeSliderControl(
                publishedValue: publishedVolume,
                displayedValue: $displayedVolume,
                accessibilityLabel: language.format("accessibility.volumeFormat", title),
                accessibilityValue: language.format(
                    "channel.volumeFormat",
                    Int(effectiveVolume.rounded())
                ),
                commit: { percent in
                    guard let channel else { return }
                    await model.setVolume(channel, percent: percent)
                }
            )
            HStack {
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

private struct HardwareVolumeIndicator: View {
    let title: String
    let status: HardwareVolumeStatus?
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        let indicator = HardwareVolumeIndicatorState.make(status: status)
        let color = color(for: indicator.tone)
        HStack(spacing: 7) {
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            Text(verbatim: language.text("systemVolume.label"))
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Spacer()
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(verbatim: indicator.valueText)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Theme.text)
            Text(verbatim: language.text(indicator.labelKey))
                .font(.caption)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.format(
            "accessibility.systemVolumeFormat",
            title,
            indicator.valueText,
            language.text(indicator.labelKey)
        ))
        .help(language.text("systemVolume.help"))
    }

    private func color(for tone: HardwareVolumeIndicatorState.Tone) -> Color {
        switch tone {
        case .healthy:
            Theme.green
        case .warning:
            Theme.amber
        case .stale:
            Theme.blue
        case .unavailable:
            Theme.muted
        }
    }
}

private struct HardwareVolumeLegend: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "hifispeaker.2.fill")
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            Text(verbatim: language.text("systemVolume.help"))
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Spacer()
            if model.isRefreshingHardwareVolume {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(language.text("systemVolume.refreshing"))
            }
            Button {
                Task { await model.refreshHardwareVolumes() }
            } label: {
                Label(
                    language.text("systemVolume.refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isRefreshingHardwareVolume)
            .accessibilityLabel(language.text("systemVolume.refresh"))
        }
        .padding(.horizontal, 4)
    }
}

private struct VolumeSliderControl: View {
    let publishedValue: Double
    @Binding var displayedValue: Double?
    let accessibilityLabel: String
    let accessibilityValue: String
    let commit: @MainActor (Int) async -> Void

    @State private var draft = VolumeSliderDraft()
    @State private var commitTask: Task<Void, Never>?
    @State private var revision = 0

    var body: some View {
        VStack(spacing: 1) {
            Slider(
                value: Binding(
                    get: {
                        draft.displayValue(published: publishedValue)
                    },
                    set: { value in
                        draft.update(value)
                        displayedValue = draft.displayValue(published: publishedValue)
                        if !draft.isDragging {
                            scheduleCommit(afterDebounce: true)
                        }
                    }
                ),
                in: 0...100,
                step: 1,
                onEditingChanged: { editing in
                    if editing {
                        revision += 1
                        commitTask?.cancel()
                        draft.beginDragging(
                            published: draft.displayValue(published: publishedValue)
                        )
                    } else {
                        scheduleCommit(afterDebounce: false)
                    }
                }
            )
            .controlSize(.large)
            .tint(Theme.blue)
            .padding(.vertical, 3)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)

            VolumeScaleView()
                .accessibilityHidden(true)
        }
        .onDisappear {
            revision += 1
            commitTask?.cancel()
        }
    }

    private func scheduleCommit(afterDebounce: Bool) {
        commitTask?.cancel()
        revision += 1
        let scheduledRevision = revision
        commitTask = Task {
            if afterDebounce {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            guard let target = draft.finishDragging() else { return }
            await commit(target)
            guard revision == scheduledRevision else { return }
            draft.completeCommit()
            displayedValue = nil
        }
    }
}

private struct VolumeScaleView: View {
    private let trackInset: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(geometry.size.width - trackInset * 2, 1)

            ZStack(alignment: .topLeading) {
                ForEach(VolumeScale.tickValues, id: \.self) { value in
                    let isMajor = VolumeScale.labeledValues.contains(value)
                    Capsule()
                        .fill(
                            isMajor
                                ? Theme.muted.opacity(0.9)
                                : Theme.muted.opacity(0.55)
                        )
                        .frame(
                            width: isMajor ? 1.5 : 1,
                            height: isMajor ? 8 : 4
                        )
                        .position(
                            x: trackInset + trackWidth * VolumeScale.fraction(for: value),
                            y: 4
                        )
                }

                ForEach(VolumeScale.labeledValues, id: \.self) { value in
                    let proposedX = trackInset + trackWidth * VolumeScale.fraction(for: value)
                    Text(verbatim: "\(value)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                        .position(
                            x: min(max(proposedX, 10), geometry.size.width - 10),
                            y: 19
                        )
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 2)
    }
}

private struct MasterControl: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @State private var displayedVolume: Double?

    private var publishedVolume: Double {
        Double(model.masterVolume)
    }

    private var effectiveVolume: Double {
        displayedVolume ?? publishedVolume
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: language.text("volume.master").uppercased())
                    .font(.caption2.bold()).foregroundStyle(Theme.muted)
                Text(verbatim: "\(Int(effectiveVolume.rounded()))%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            VolumeSliderControl(
                publishedValue: publishedVolume,
                displayedValue: $displayedVolume,
                accessibilityLabel: language.text("accessibility.masterVolume"),
                accessibilityValue: "\(Int(effectiveVolume.rounded()))%",
                commit: { percent in
                    await model.setMaster(percent)
                }
            )
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
