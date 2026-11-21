# Native macOS Console

The native application, `MacBook Stereo Pair.app`, is the primary interface for
the stereo pair. It controls and observes the audio runtime but does not carry
audio itself. Closing the window or quitting the GUI never stops playback.

Snapweb remains available as an optional diagnostic browser interface during
the transition. It receives no new features until the native application has
complete functional parity.

## Runtime and Interface Relationship

```text
MacStereoPair.app --------+
                          | Unix socket
mac-stereo-pairctl -------+------> StereoPairAgent
                                      |
                                      +---- launchctl
                                      +---- local Snapserver API
                                      +---- shared audio meters

snapweb-stereo-pair ------> local Snapserver HTTP API
```

The control socket is:

```text
~/Library/Application Support/Snapcast/run/control.sock
```

Its mode is `0600`, and connections from another user are rejected. HTTP and
TCP control APIs remain bound to localhost. Uncompressed audio port `1704`
requires a trusted LAN, VPN, or restrictive firewall.

## Two Audio Modes

The high-level modes are:

- **Stereo pair**: BlackHole captures macOS output, the splitter creates
  `LeftAudio` and `RightAudio`, and both Snapclients play their assigned side.
- **Mac system audio**: the runtime is stopped, services are intentionally
  disabled, and the last non-BlackHole output is restored. If that device is no
  longer available, the configured built-in speaker is used.

The exact physical output volume is restored before switching back. This applies
to both Macs and prevents a hand-back transition from unexpectedly jumping to
100%.

BlackHole remains installed in system mode. It is only made inactive by the
audio route, and the runtime never unloads or deletes the driver.

The menu-bar application provides mode, status, volume, mute, reconnect,
console, and quit-GUI actions. The main window provides:

- master volume with preserved left/right offsets;
- per-side volume, mute, delay, route, format, and connection state;
- live peak/RMS waveform meters and clip indication;
- service, routing, and wake-recovery status;
- an advanced sheet for logs, redacted export, versions, diagnostics, and
  allowlisted service restarts.

## Health and Notifications

Health is reported independently from the selected audio mode. Expected stops
in system mode are shown as disabled rather than failed.

The notification rules use grace periods:

- local service failures settle for 3 seconds;
- a disconnected client settles for 6 seconds;
- wake recovery has up to 30 seconds to complete.

One incident produces one notification. Repeated snapshots do not repeat it.
When the affected component recovers, the incident resets so a later failure can
notify again. Notification permission is requested only after setup succeeds,
not when the application launches.

## First-Run Setup

The wizard has four persistent stages after the welcome page:

1. dependency checks;
2. local runtime installation;
3. remote Mac connection;
4. final verification.

Checks cover Xcode Command Line Tools, Homebrew, BlackHole, PortAudio, OpenSSH,
the control Agent, and installed runtime files. Homebrew is probed at both:

```text
/opt/homebrew/bin/brew
/usr/local/bin/brew
```

Passwords are entered only in Terminal. The app generates a fixed-argument
script, opens it with Terminal, and polls for completion. It never reads or
stores a local administrator password or a remote SSH password.

The remote step creates or reuses an SSH key, uses `ssh-copy-id` only when
needed, verifies key-only access with `BatchMode=yes`, installs the remote
helper, and writes a local non-secret `remote-control.json`.

## Diagnostics and Privacy

Redacted diagnostics remove home paths, SSH targets, IP addresses, and token-like
values. The export is created only after an explicit user action and is never
uploaded automatically.

The service maintenance action accepts only the fixed runtime LaunchAgent IDs.
The protocol never accepts an executable path or shell fragment.

## Languages and Accessibility

English and Simplified Chinese resources ship with the application. It follows
the system language by default and provides an in-app override.

Status LEDs always include text or accessibility labels. Reduce Motion stops LED
pulses while preserving the semantic status. The main controls expose VoiceOver
labels and keyboard actions.

## Packaging

The first release builds from source and is ad-hoc signed. It is not notarized,
does not require paid Apple Developer membership, has no App Store dependency,
and has no automatic updater. See [installation.md](installation.md) and
[homebrew.md](homebrew.md) for distribution details.

## Reinstall and Upgrade

Installation is manifest-driven. The installer writes:

```text
~/Library/Application Support/Snapcast/state/installation.json
```

Repeated installation checks:

- product and config schema versions;
- control protocol version;
- required app, Agent, CLI, runtime, script, and LaunchAgent files;
- a digest of installed executable, generated service, pairing configuration,
  and remote control files.

An unchanged installation is left running. Missing or changed files trigger a
repair, a newer product version triggers an upgrade, and an older product
version is rejected unless the user explicitly forces a downgrade.

The user-facing force override is always available at **Advanced Diagnostics →
Installation maintenance → Force reinstall current version**. It deliberately
skips the “already installed” decision and rebuilds all program and service
files. Configuration, remote control state, logs, and preferences remain in
place. Removing configuration must remain a separate, explicit destructive
action.
