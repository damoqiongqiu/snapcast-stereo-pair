import StereoPairCore
import SwiftUI

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @EnvironmentObject private var notifications: NotificationManager
    @State private var showsAdvanced = false

    var body: some View {
        consoleContent
            .frame(maxWidth: MainWindowMetrics.contentMaxWidth)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        VStack(spacing: 14) {
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

    private var publishedVolume: Double {
        Double(channel?.volume ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
            ChannelWaveform(
                channel: channel
            )
                .padding(.horizontal, 2)
            HardwareVolumeIndicator(
                title: title,
                status: hardwareVolume
            )
            VolumeSliderControl(
                publishedValue: publishedVolume,
                label: language.text("volume.snapcast"),
                layout: .inline,
                formatValue: { value in
                    language.format("channel.volumeFormat", value)
                },
                accessibilityLabel: language.format("accessibility.volumeFormat", title),
                interactionChanged: { editing in
                    if editing {
                        model.beginVolumeInteraction()
                    } else {
                        model.endVolumeInteraction()
                    }
                },
                commit: { percent in
                    guard let channel else { return }
                    await model.setVolume(channel, percent: percent)
                }
            )
            HStack(spacing: 12) {
                Toggle(language.text("mute.label"), isOn: Binding(
                    get: { channel?.muted ?? false },
                    set: { value in
                        if let channel { Task { await model.setMute(channel, muted: value) } }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(language.format("accessibility.muteFormat", title))
                Spacer()
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
                .controlSize(.mini)
                .accessibilityLabel(language.format("accessibility.latencyFormat", title))
            }
            .font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(12)
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
                ZStack {
                    Circle().fill(Theme.raised)
                    if model.isRefreshingHardwareVolume {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshingHardwareVolume)
            .accessibilityLabel(language.text("systemVolume.refresh"))
            .help(language.text("systemVolume.refresh"))
        }
    }
}

private enum VolumeSliderLayout {
    case inline
    case prominent
}

private struct VolumeSliderControl: View {
    let publishedValue: Double
    let label: String
    let layout: VolumeSliderLayout
    let formatValue: @MainActor (Int) -> String
    let accessibilityLabel: String
    let interactionChanged: @MainActor (Bool) -> Void
    let commit: @MainActor (Int) async -> Void

    @State private var draft = VolumeSliderDraft()
    @State private var pump = VolumeCommitPump()
    @State private var interactionActive = false

    var body: some View {
        Group {
            switch layout {
            case .inline:
                VStack(spacing: 1) {
                    valueHeader
                    slider
                }
            case .prominent:
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: label.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.muted)
                        Text(verbatim: formatValue(currentValue))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    slider
                }
            }
        }
        .accessibilityRepresentation {
            Slider(
                value: Binding(
                    get: {
                        draft.displayValue(published: publishedValue)
                    },
                    set: { value in
                        draft.update(value)
                        startCommitSession()
                        pump.finish(
                            Int(value.rounded()),
                            delay: .milliseconds(180)
                        )
                    }
                ),
                in: 0...100
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(formatValue(currentValue))
            .accessibilityAdjustableAction { direction in
                let delta: Int
                switch direction {
                case .increment:
                    delta = 1
                case .decrement:
                    delta = -1
                @unknown default:
                    return
                }
                adjust(by: delta)
            }
        }
        .onDisappear {
            pump.cancel()
            endInteraction()
        }
    }

    private var currentValue: Int {
        Int(draft.displayValue(published: publishedValue).rounded())
    }

    private var valueHeader: some View {
        HStack {
            Text(verbatim: label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(verbatim: formatValue(currentValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.text)
        }
    }

    private var slider: some View {
        VStack(spacing: 1) {
            VolumeSliderSurface(
                value: draft.displayValue(published: publishedValue),
                onEditingStarted: {
                    startCommitSession()
                    draft.beginDragging(
                        published: draft.displayValue(published: publishedValue)
                    )
                },
                onValueChanged: { value in
                    draft.update(value)
                    pump.preview(Int(value.rounded()))
                },
                onEditingEnded: { value in
                    draft.update(value)
                    pump.finish(Int(value.rounded()))
                },
                onAdjust: { delta in
                    adjust(by: delta)
                }
            )
            .padding(.vertical, 3)

            VolumeScaleView()
                .accessibilityHidden(true)
        }
    }

    private func adjust(by delta: Int) {
        let target = min(100, max(0, currentValue + delta))
        draft.update(Double(target))
        startCommitSession()
        pump.finish(target, delay: .milliseconds(180))
    }

    private func startCommitSession() {
        if !interactionActive {
            interactionActive = true
            interactionChanged(true)
        }
        pump.begin(
            commit: commit,
            onFinalCommit: {
                draft.completeCommit()
                endInteraction()
            }
        )
    }

    private func endInteraction() {
        guard interactionActive else { return }
        interactionActive = false
        interactionChanged(false)
    }
}

private struct VolumeSliderSurface: View {
    let value: Double
    let onEditingStarted: () -> Void
    let onValueChanged: (Double) -> Void
    let onEditingEnded: (Double) -> Void
    let onAdjust: (Int) -> Void

    @State private var isDragging = false
    @State private var showsKeyboardFocus = false
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            VolumeSliderVisual(value: value)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                isFocused = true
                                showsKeyboardFocus = false
                                onEditingStarted()
                            }
                            onValueChanged(VolumeSliderGeometry.value(
                                at: gesture.location.x,
                                in: geometry.size.width
                            ))
                        }
                        .onEnded { gesture in
                            let finalValue = VolumeSliderGeometry.value(
                                at: gesture.location.x,
                                in: geometry.size.width
                            )
                            isDragging = false
                            onEditingEnded(finalValue)
                        }
                )
        }
        .frame(height: VolumeSliderGeometry.controlHeight)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) {
            showsKeyboardFocus = true
            onAdjust(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            showsKeyboardFocus = true
            onAdjust(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            showsKeyboardFocus = true
            onAdjust(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            showsKeyboardFocus = true
            onAdjust(1)
            return .handled
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                showsKeyboardFocus = false
            }
        }
        .overlay {
            if isFocused && showsKeyboardFocus {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Theme.blue.opacity(0.8), lineWidth: 1)
            }
        }
    }
}

private struct VolumeSliderVisual: View {
    let value: Double

    var body: some View {
        Canvas { context, size in
            let bounds = VolumeSliderGeometry.trackBounds(in: size.width)
            let centerY = size.height / 2
            let knobX = VolumeSliderGeometry.x(for: value, in: size.width)
            let stroke = StrokeStyle(
                lineWidth: VolumeSliderGeometry.trackHeight,
                lineCap: .round
            )

            var track = Path()
            track.move(to: CGPoint(x: bounds.lowerBound, y: centerY))
            track.addLine(to: CGPoint(x: bounds.upperBound, y: centerY))
            context.stroke(
                track,
                with: .color(Theme.muted.opacity(0.34)),
                style: stroke
            )

            if knobX > bounds.lowerBound {
                var fill = Path()
                fill.move(to: CGPoint(x: bounds.lowerBound, y: centerY))
                fill.addLine(to: CGPoint(x: knobX, y: centerY))
                context.stroke(fill, with: .color(Theme.blue), style: stroke)
            }

            let knobRect = CGRect(
                x: knobX - VolumeSliderGeometry.knobDiameter / 2,
                y: centerY - VolumeSliderGeometry.knobDiameter / 2,
                width: VolumeSliderGeometry.knobDiameter,
                height: VolumeSliderGeometry.knobDiameter
            )
            context.fill(
                Path(ellipseIn: knobRect),
                with: .color(Theme.muted.opacity(0.82))
            )
        }
    }
}

private struct VolumeScaleView: View {
    var body: some View {
        GeometryReader { geometry in
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
                            x: VolumeSliderGeometry.x(
                                for: Double(value),
                                in: geometry.size.width
                            ),
                            y: 4
                        )
                }

                ForEach(VolumeScale.labeledValues, id: \.self) { value in
                    let proposedX = VolumeSliderGeometry.x(
                        for: Double(value),
                        in: geometry.size.width
                    )
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
    }
}

private struct MasterControl: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage

    private var publishedVolume: Double {
        Double(model.masterVolume)
    }

    var body: some View {
        VolumeSliderControl(
            publishedValue: publishedVolume,
            label: language.text("volume.master"),
            layout: .prominent,
            formatValue: { "\($0)%" },
            accessibilityLabel: language.text("accessibility.masterVolume"),
            interactionChanged: { editing in
                if editing {
                    model.beginVolumeInteraction()
                } else {
                    model.endVolumeInteraction()
                }
            },
            commit: { percent in
                await model.setMaster(percent)
            }
        )
        .padding(12)
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
