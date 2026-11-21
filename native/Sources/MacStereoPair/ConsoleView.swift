import StereoPairCore
import SwiftUI

struct ConsoleView: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacBook Stereo Pair").font(.title2.bold())
                    Text("48 kHz · 24-bit PCM · \(model.snapshot?.mode.rawValue ?? "starting")")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(model.healthy ? "正常" : "需要注意")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(model.healthy ? Theme.green.opacity(0.18) : Theme.amber.opacity(0.18))
                    .foregroundStyle(model.healthy ? Theme.green : Theme.amber)
                    .clipShape(Capsule())
            }

            Picker("音频模式", selection: Binding(
                get: { model.isSnapcast ? AudioMode.snapcast : .system },
                set: { mode in Task { await model.setMode(mode) } }
            )) {
                Text("立体声配对").tag(AudioMode.snapcast)
                Text("Mac 系统音频").tag(AudioMode.system)
            }
            .pickerStyle(.segmented)
            .disabled(model.isWorking)

            HStack(spacing: 14) {
                ChannelStrip(title: "左侧", channel: model.left, model: model)
                ChannelStrip(title: "右侧", channel: model.right, model: model)
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
}

private struct ChannelStrip: View {
    let title: String
    let channel: ChannelStatus?
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(channel?.connected == true ? Theme.green : Theme.red).frame(width: 7, height: 7)
                Text("\(title) · \(channel?.clientId ?? "未连接")").font(.headline)
                Spacer()
                Text(channel?.streamId ?? "—").font(.caption).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<18, id: \.self) { index in
                    let level = meterLevel(index)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index > 15 ? Theme.red : index > 12 ? Theme.amber : Theme.green)
                        .frame(width: 7, height: 8 + CGFloat(index % 4) * 6)
                        .opacity(level)
                }
            }
            .frame(height: 70, alignment: .bottom)
            Slider(
                value: Binding(
                    get: { Double(channel?.volume ?? 0) },
                    set: { value in
                        if let channel { Task { await model.setVolume(channel, percent: Int(value)) } }
                    }
                ),
                in: 0...100
            )
            HStack {
                Text("音量 \(channel?.volume ?? 0)%")
                Spacer()
                Toggle("静音", isOn: Binding(
                    get: { channel?.muted ?? false },
                    set: { value in
                        if let channel { Task { await model.setMute(channel, muted: value) } }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .font(.caption).foregroundStyle(Theme.muted)
            Stepper(
                "延迟 \(channel?.latencyMs ?? 0) ms",
                value: Binding(
                    get: { channel?.latencyMs ?? 0 },
                    set: { value in
                        if let channel { Task { await model.setLatency(channel, milliseconds: value) } }
                    }
                ),
                in: 0...500
            )
            .font(.caption)
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator))
    }

    private func meterLevel(_ index: Int) -> Double {
        guard let peak = channel?.peakDb, peak > -60 else { return 0.12 }
        let normalized = (peak + 60) / 60
        return Double(index) / 18.0 < normalized ? 1 : 0.12
    }
}

private struct MasterControl: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MASTER").font(.caption2.bold()).foregroundStyle(Theme.muted)
                Text("\(model.masterVolume)%").font(.system(size: 32, weight: .bold, design: .rounded))
            }
            Slider(
                value: Binding(
                    get: { Double(model.masterVolume) },
                    set: { value in Task { await model.setMaster(Int(value)) } }
                ),
                in: 0...100
            )
        }
        .padding(14)
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatusBus: View {
    @ObservedObject var model: ConsoleViewModel

    var body: some View {
        HStack(spacing: 0) {
            zone("CONTROL", items: [
                ("Snapserver", model.snapshot?.services.first(where: { $0.id.contains("server") })?.state == .running)
            ])
            zone("AUDIO PATH", items: [
                ("Splitter", model.snapshot?.services.first(where: { $0.id.contains("splitter") })?.state == .running),
                ("Clients", model.left?.connected == true && model.right?.connected == true)
            ])
            zone("ROUTING", items: [
                ("Left / Right", model.snapshot?.issues.isEmpty == true)
            ])
            zone("RECOVERY", items: [
                ("Wake", model.snapshot?.services.first(where: { $0.id.contains("wake") })?.state == .running)
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
                    Text(item.0).font(.system(size: 10))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.separator).frame(width: 1) }
    }
}

struct MenuBarContent: View {
    @ObservedObject var model: ConsoleViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.isSnapcast ? "立体声配对：\(model.healthy ? "正常" : "异常")" : "Mac 系统音频")
        Divider()
        Button("打开控制台") { openWindow(id: "console") }
        Button("启用立体声配对") { Task { await model.setMode(.snapcast) } }
        Button("切换到 Mac 系统音频") { Task { await model.setMode(.system) } }
        Divider()
        Text("总音量 \(model.masterVolume)%")
        Button("退出界面") { NSApplication.shared.terminate(nil) }
    }
}
