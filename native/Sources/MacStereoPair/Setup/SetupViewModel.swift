import Foundation
import StereoPairCore
import SwiftUI

private let externalSetupDependencies: [SetupDependency] = [
    .xcodeCommandLineTools,
    .homebrew,
    .blackHole,
    .portAudio,
    .ssh
]

enum SetupStep: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case welcome
    case dependencies
    case localRuntime
    case remoteMac
    case verification

    var id: Int { rawValue }

    static func < (lhs: SetupStep, rhs: SetupStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var titleKey: String {
        switch self {
        case .welcome:
            return "setup.welcome"
        case .dependencies:
            return "setup.dependencies"
        case .localRuntime:
            return "setup.localRuntime"
        case .remoteMac:
            return "setup.remoteMac"
        case .verification:
            return "setup.verification"
        }
    }
}

struct SetupFlowState: Equatable {
    private(set) var completed: Set<SetupStep>
    private(set) var currentStep: SetupStep
    private(set) var pendingAction: SetupAction?
    private(set) var lastError: String?

    init(completed: Set<SetupStep> = []) {
        self.completed = completed
        currentStep = SetupStep.allCases.first { !completed.contains($0) } ?? .verification
    }

    var isConsoleEnabled: Bool {
        completed.contains(.verification)
    }

    mutating func complete(_ step: SetupStep) {
        completed.insert(step)
        currentStep = SetupStep.allCases.first { !completed.contains($0) } ?? .verification
        pendingAction = nil
        lastError = nil
    }

    mutating func show(_ step: SetupStep) {
        currentStep = step
    }

    mutating func beginLocalInstall() {
        pendingAction = .installLocalRuntime
        lastError = nil
    }

    mutating func beginRemoteSetup(user: String, host: String) throws {
        pendingAction = try SetupAction.configureRemote(user: user, host: host)
        lastError = nil
    }

    mutating func applyChecks(_ checks: [SetupCheck]) {
        let dependenciesReady = externalSetupDependencies.allSatisfy { dependency in
            checks.first(where: { $0.dependency == dependency })?.status == .ready
        }
        if dependenciesReady, currentStep == .dependencies {
            complete(.dependencies)
        }
        if pendingAction == .installLocalRuntime,
           checks.first(where: { $0.dependency == .runtime })?.status == .ready {
            complete(.localRuntime)
        }
    }

    mutating func recordRemoteReady() {
        guard currentStep == .remoteMac else { return }
        complete(.remoteMac)
    }

    mutating func recordFailure(_ message: String) {
        pendingAction = nil
        lastError = message
    }

    mutating func finishVerification(allChecksReady: Bool) {
        currentStep = .verification
        if allChecksReady {
            complete(.verification)
        }
    }
}

private struct RemoteControlMarker: Decodable {
    let user: String
    let host: String
}

enum SetupRemoteMarker {
    static func matches(_ data: Data, user: String, host: String) -> Bool {
        guard let marker = try? JSONDecoder().decode(RemoteControlMarker.self, from: data) else {
            return false
        }
        return marker.user == user && marker.host == host
    }
}

@MainActor
final class SetupViewModel: ObservableObject {
    @Published private(set) var flow: SetupFlowState
    @Published private(set) var checks: [SetupCheck] = []
    @Published private(set) var isRefreshing = false
    @Published var remoteUser = ""
    @Published var remoteHost = ""
    @Published var message: String?

    private let probe: SetupProbe
    private let terminalLauncher: TerminalLauncher
    private let supportDirectory: URL
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?

    private static let completedStepsKey = "setup.completed-steps"

    init(
        probe: SetupProbe = SetupProbe(),
        terminalLauncher: TerminalLauncher = TerminalLauncher(),
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Snapcast"),
        defaults: UserDefaults = .standard
    ) {
        self.probe = probe
        self.terminalLauncher = terminalLauncher
        self.supportDirectory = supportDirectory
        self.defaults = defaults
        let rawSteps = defaults.array(forKey: Self.completedStepsKey) as? [Int] ?? []
        flow = SetupFlowState(
            completed: Set(rawSteps.compactMap(SetupStep.init(rawValue:)))
        )
    }

    func start() async {
        TerminalScriptBuilder.removeExpiredScripts(in: supportDirectory)
        await refreshChecks()
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                if flow.pendingAction != nil {
                    await refreshChecks()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refreshChecks() async {
        isRefreshing = true
        defer { isRefreshing = false }
        checks = await probe.checkAll()
        var updated = flow
        updated.applyChecks(checks)
        if updated.currentStep == .remoteMac,
           updated.pendingAction != nil,
           remoteSetupMarkerReady {
            updated.recordRemoteReady()
        }
        persist(updated.completed)
        flow = updated
    }

    func completeWelcome() {
        flow.complete(.welcome)
        persist(flow.completed)
    }

    func showStep(_ step: SetupStep) {
        flow.show(step)
    }

    var externalDependenciesReady: Bool {
        externalSetupDependencies.allSatisfy { dependency in
            checks.first(where: { $0.dependency == dependency })?.status == .ready
        }
    }

    var remoteConfigurationReady: Bool {
        remoteSetupMarkerReady
    }

    func completeDependencies() {
        guard externalDependenciesReady else { return }
        flow.complete(.dependencies)
        persist(flow.completed)
    }

    func completeLocalRuntime() {
        guard checks.first(where: { $0.dependency == .runtime })?.status == .ready else { return }
        flow.complete(.localRuntime)
        persist(flow.completed)
    }

    func beginLocalInstall() {
        do {
            let helperURL = try setupHelperURL()
            let scriptURL = try TerminalScriptBuilder.writeScript(
                action: .installLocalRuntime,
                helperURL: helperURL,
                supportDirectory: supportDirectory
            )
            try terminalLauncher.open(scriptURL)
            flow.beginLocalInstall()
            message = nil
        } catch {
            flow.recordFailure(error.localizedDescription)
            message = error.localizedDescription
        }
    }

    func beginRemoteSetup() {
        do {
            try flow.beginRemoteSetup(user: remoteUser, host: remoteHost)
            let action = try SetupAction.configureRemote(user: remoteUser, host: remoteHost)
            let scriptURL = try TerminalScriptBuilder.writeScript(
                action: action,
                helperURL: try setupHelperURL(),
                supportDirectory: supportDirectory
            )
            try terminalLauncher.open(scriptURL)
            message = nil
        } catch {
            flow.recordFailure(error.localizedDescription)
            message = error.localizedDescription
        }
    }

    func completeRemoteSetup() {
        flow.recordRemoteReady()
        persist(flow.completed)
    }

    func finishVerification(snapshot: RuntimeSnapshot?) {
        let ready = checks.allSatisfy { $0.status == .ready } &&
            snapshot?.channels.count == 2 &&
            snapshot?.channels.allSatisfy(\.connected) == true
        flow.finishVerification(allChecksReady: ready)
        persist(flow.completed)
        if !ready {
            message = "The local pair is not ready yet."
        }
    }

    func skipSetup() {
        let allSteps = Set(SetupStep.allCases)
        flow = SetupFlowState(completed: allSteps)
        persist(allSteps)
    }

    private func persist(_ completed: Set<SetupStep>) {
        defaults.set(completed.map(\.rawValue).sorted(), forKey: Self.completedStepsKey)
    }

    private func setupHelperURL() throws -> URL {
        let candidates = [
            ProcessInfo.processInfo.environment["SNAPCAST_SETUP_HELPER"],
            supportDirectory.appendingPathComponent("setup/native-setup-helper.sh").path,
            supportDirectory.appendingPathComponent("bin/native-setup-helper.sh").path,
            "/opt/homebrew/share/macbook-stereo-pair/integration/scripts/native-setup-helper.sh",
            "/usr/local/share/macbook-stereo-pair/integration/scripts/native-setup-helper.sh"
        ].compactMap { $0 }
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw TerminalLauncherError.couldNotCreateScript
    }

    private var remoteSetupMarkerReady: Bool {
        guard !remoteUser.isEmpty, !remoteHost.isEmpty else { return false }
        let url = supportDirectory.appendingPathComponent("state/remote-control.json")
        guard let data = try? Data(contentsOf: url) else { return false }
        return SetupRemoteMarker.matches(data, user: remoteUser, host: remoteHost)
    }
}
