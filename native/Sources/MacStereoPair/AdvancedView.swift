import AppKit
import StereoPairCore
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedView: View {
    @ObservedObject var model: ConsoleViewModel
    @EnvironmentObject private var language: AppLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics = ""
    @State private var exportRedacted = true
    @State private var statusMessage: String?
    @State private var restartingServiceID: String?
    @State private var showsReinstallConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: language.text("advanced.title"))
                        .font(.title2.bold())
                    Text(verbatim: language.text("advanced.subtitle"))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button(language.text("advanced.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider().overlay(Theme.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    versionCard
                    maintenanceCard
                    diagnosticsCard
                    serviceCard
                    rawSnapshotCard
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .confirmationDialog(
            language.text("advanced.reinstallTitle"),
            isPresented: $showsReinstallConfirmation
        ) {
            Button(language.text("advanced.reinstallConfirm"), role: .destructive) {
                forceReinstall()
            }
            Button(language.text("advanced.reinstallCancel"), role: .cancel) {}
        } message: {
            Text(verbatim: language.text("advanced.reinstallHelp"))
        }
    }

    private var versionCard: some View {
        HStack(spacing: 10) {
            versionPill("Runtime", nativeRuntimeVersion)
            versionPill("Protocol", "\(model.snapshot?.protocolVersion ?? controlProtocolVersion)")
            Spacer()
            Button(language.text("advanced.openLogs"), action: openLogsDirectory)
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: language.text("advanced.diagnostics"))
                .font(.headline)
            Text(verbatim: language.text("advanced.diagnosticsHelp"))
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Toggle(language.text("advanced.redacted"), isOn: $exportRedacted)
            HStack {
                Button(language.text("advanced.export")) {
                    Task {
                        diagnostics = await model.exportDiagnostics(redacted: exportRedacted) ?? ""
                        statusMessage = diagnostics.isEmpty
                            ? language.text("advanced.exportFailed")
                            : language.text("advanced.exportReady")
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(language.text("advanced.save")) {
                    saveDiagnostics()
                }
                .disabled(diagnostics.isEmpty)

                Button(language.text("advanced.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics, forType: .string)
                    statusMessage = language.text("advanced.copied")
                }
                .disabled(diagnostics.isEmpty)
                Spacer()
                if let statusMessage {
                    Text(verbatim: statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var maintenanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: language.text("advanced.maintenance"))
                .font(.headline)
            Text(verbatim: language.text("advanced.reinstallDescription"))
                .font(.caption)
                .foregroundStyle(Theme.muted)
            HStack {
                Button(language.text("advanced.reinstall")) {
                    showsReinstallConfirmation = true
                }
                Spacer()
                if let statusMessage {
                    Text(verbatim: statusMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: language.text("advanced.services"))
                .font(.headline)
            if let services = model.snapshot?.services, !services.isEmpty {
                ForEach(services, id: \.id) { service in
                    HStack(spacing: 10) {
                        ServiceLED(
                            appearance: ServiceLEDAppearance.resolve(
                                state: service.state,
                                freshActivity: (service.lastSuccessAgeSeconds ?? .infinity) <= 2
                            ),
                            label: language.text(serviceLabelKey(service.id)),
                            statusText: language.text(
                                ServiceLEDAppearance.resolve(
                                    state: service.state,
                                    freshActivity: false
                                ).labelKey
                            )
                        )
                        Spacer()
                        if let pid = service.pid {
                            Text(verbatim: "PID \(pid)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.muted)
                        }
                        Button(language.text("advanced.restart")) {
                            restart(service)
                        }
                        .disabled(restartingServiceID != nil)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text(verbatim: language.text("advanced.noServices"))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rawSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: language.text("advanced.rawSnapshot"))
                .font(.headline)
            ScrollView([.horizontal, .vertical]) {
                Text(verbatim: rawSnapshot)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .padding(10)
            .background(Theme.background.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var rawSnapshot: String {
        guard let snapshot = model.snapshot else {
            return language.text("advanced.noSnapshot")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            return language.text("advanced.noSnapshot")
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func versionPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.muted)
            Text(verbatim: value)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.raised)
        .clipShape(Capsule())
    }

    private func restart(_ service: ServiceStatus) {
        restartingServiceID = service.id
        Task {
            await model.restartService(id: service.id)
            restartingServiceID = nil
        }
    }

    private func openLogsDirectory() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Snapcast", isDirectory: true)
        NSWorkspace.shared.open(logs)
    }

    private func saveDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "macbook-stereo-pair-diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try diagnostics.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = language.text("advanced.saved")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func forceReinstall() {
        do {
            let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Snapcast")
            let helperURL = try InstallationSupport.helperURL(
                supportDirectory: supportDirectory
            )
            let scriptURL = try TerminalScriptBuilder.writeScript(
                action: .forceReinstallCurrentVersion,
                helperURL: helperURL,
                supportDirectory: supportDirectory
            )
            try TerminalLauncher().open(scriptURL)
            statusMessage = language.text("advanced.reinstallOpened")
        } catch {
            statusMessage = language.text("advanced.reinstallFailed")
        }
    }

    private func serviceLabelKey(_ id: String) -> String {
        switch id {
        case "com.snapcast.server":
            return "service.snapserver"
        case "com.snapcast.splitter":
            return "service.splitter"
        case "com.snapcast.local-client":
            return "service.localClient"
        case "com.snapcast.pairing":
            return "service.pairing"
        case "com.snapcast.wake-recovery":
            return "service.wakeRecovery"
        default:
            return "status.control"
        }
    }
}
