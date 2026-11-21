import Foundation

public enum SetupDependency: String, CaseIterable, Codable, Sendable {
    case xcodeCommandLineTools
    case homebrew
    case blackHole
    case portAudio
    case runtime
    case ssh
}

public enum SetupCheckStatus: String, Equatable, Sendable {
    case ready
    case missing
    case outdated
    case malformed
}

public struct SetupCheck: Equatable, Sendable, Identifiable {
    public let dependency: SetupDependency
    public let status: SetupCheckStatus
    public let version: String?
    public let remediationKey: String?

    public var id: SetupDependency { dependency }

    public init(
        dependency: SetupDependency,
        status: SetupCheckStatus,
        version: String? = nil,
        remediationKey: String? = nil
    ) {
        self.dependency = dependency
        self.status = status
        self.version = version
        self.remediationKey = remediationKey
    }
}

public enum SetupValidationError: Error, Equatable {
    case invalidRemoteUser
    case invalidRemoteHost
}

public enum SetupAction: Equatable, Sendable {
    case installLocalRuntime
    case forceReinstallCurrentVersion
    case remoteConfiguration(user: String, host: String)

    public init(user: String, host: String) throws {
        guard user.range(of: #"^[A-Za-z0-9._-]{1,64}$"#, options: .regularExpression) != nil else {
            throw SetupValidationError.invalidRemoteUser
        }
        guard host.range(
            of: #"^(?:[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251})|\[[0-9A-Fa-f:]+\])$"#,
            options: .regularExpression
        ) != nil else {
            throw SetupValidationError.invalidRemoteHost
        }
        self = .remoteConfiguration(user: user, host: host)
    }

    public static func configureRemote(user: String, host: String) throws -> SetupAction {
        try SetupAction(user: user, host: host)
    }

    public var arguments: [String] {
        switch self {
        case .installLocalRuntime:
            return ["install-local"]
        case .forceReinstallCurrentVersion:
            return ["force-reinstall"]
        case .remoteConfiguration(let user, let host):
            return ["configure-remote", user, host]
        }
    }
}

public enum SetupResultParser {
    public static func xcode(status: Int32, output: String) -> SetupCheck {
        guard status == 0 else {
            return SetupCheck(
                dependency: .xcodeCommandLineTools,
                status: .missing,
                remediationKey: "setup.remediation.xcode"
            )
        }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.contains("CommandLineTools") || path.contains(".app/Contents/Developer") else {
            return SetupCheck(
                dependency: .xcodeCommandLineTools,
                status: .malformed,
                remediationKey: "setup.remediation.xcode"
            )
        }
        return SetupCheck(dependency: .xcodeCommandLineTools, status: .ready)
    }

    public static func homebrew(status: Int32, output: String) -> SetupCheck {
        guard status == 0 else {
            return missing(.homebrew, remediationKey: "setup.remediation.homebrew")
        }
        guard let version = firstCapture(
            in: output,
            pattern: #"Homebrew\s+([0-9]+(?:\.[0-9]+)+)"#
        ) else {
            return malformed(.homebrew, remediationKey: "setup.remediation.homebrew")
        }
        return versioned(.homebrew, version: version, minimum: "4.0.0")
    }

    public static func audioDevices(status: Int32, json: String) -> SetupCheck {
        guard status == 0 else {
            return missing(.blackHole, remediationKey: "setup.remediation.blackHole")
        }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return malformed(.blackHole, remediationKey: "setup.remediation.blackHole")
        }
        guard containsDevice(named: "BlackHole", in: object) else {
            return missing(.blackHole, remediationKey: "setup.remediation.blackHole")
        }
        return SetupCheck(dependency: .blackHole, status: .ready)
    }

    public static func portAudio(status: Int32, output: String) -> SetupCheck {
        guard status == 0 else {
            return missing(.portAudio, remediationKey: "setup.remediation.portAudio")
        }
        guard let version = firstCapture(
            in: output,
            pattern: #"portaudio\s+([0-9]+(?:\.[0-9]+)+)"#,
            options: [.caseInsensitive]
        ) else {
            return malformed(.portAudio, remediationKey: "setup.remediation.portAudio")
        }
        return versioned(.portAudio, version: version, minimum: "19.7.0")
    }

    public static func runtime(files: [String: Bool]) -> SetupCheck {
        let required = ["set-mode.sh", "bin/StereoPairAgent", "bin/mac-stereo-pairctl"]
        guard required.allSatisfy({ files[$0] == true }) else {
            return missing(.runtime, remediationKey: "setup.remediation.runtime")
        }
        return SetupCheck(dependency: .runtime, status: .ready, version: nativeRuntimeVersion)
    }

    public static func ssh(status: Int32, output: String) -> SetupCheck {
        guard status == 0 else {
            return missing(.ssh, remediationKey: "setup.remediation.ssh")
        }
        guard let version = firstCapture(in: output, pattern: #"OpenSSH_([0-9]+(?:\.[0-9]+)?)"#) else {
            return malformed(.ssh, remediationKey: "setup.remediation.ssh")
        }
        return versioned(.ssh, version: version, minimum: "8.0")
    }

    private static func missing(
        _ dependency: SetupDependency,
        remediationKey: String
    ) -> SetupCheck {
        SetupCheck(dependency: dependency, status: .missing, remediationKey: remediationKey)
    }

    private static func malformed(
        _ dependency: SetupDependency,
        remediationKey: String
    ) -> SetupCheck {
        SetupCheck(dependency: dependency, status: .malformed, remediationKey: remediationKey)
    }

    private static func versioned(
        _ dependency: SetupDependency,
        version: String,
        minimum: String
    ) -> SetupCheck {
        SetupCheck(
            dependency: dependency,
            status: compareVersions(version, minimum) >= 0 ? .ready : .outdated,
            version: version,
            remediationKey: "setup.remediation.\(dependency.rawValue)"
        )
    }

    private static func firstCapture(
        in value: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[capture])
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart != rightPart {
                return leftPart < rightPart ? -1 : 1
            }
        }
        return 0
    }

    private static func containsDevice(named name: String, in object: Any) -> Bool {
        if let dictionary = object as? [String: Any] {
            return dictionary.values.contains { containsDevice(named: name, in: $0) }
        }
        if let array = object as? [Any] {
            return array.contains { containsDevice(named: name, in: $0) }
        }
        if let value = object as? String {
            return value.localizedCaseInsensitiveContains(name)
        }
        return false
    }
}
