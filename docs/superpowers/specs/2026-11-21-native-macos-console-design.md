# Native macOS Stereo Console Design

## Status

Approved for implementation planning.

## Goal

Add a native SwiftUI control application to the Snapcast runtime repository so a
user can choose which side of the system owns macOS audio, operate the stereo
pair, inspect channel activity, and see service failures without opening a web
interface or reading logs.

## Context

The current runtime has a reliable headless audio path and a separate Snapweb
controller. The native application becomes the primary interface. It controls
the complete runtime stack rather than individual processes and observes
health independently from the GUI.

Snapweb remains available during the transition as an optional diagnostic
interface. It receives no new features until the native application reaches
functional parity. Its retirement decision is separate from this design.

## Product Principles

- Keep the audio engine in independent launchd processes. A GUI failure must
  never stop playback.
- Model "Mac system audio" and "Snapcast stereo pair" as two high-level audio
  modes. Do not expose individual service start/stop as the primary workflow.
- Treat BlackHole as an installed CoreAudio device that becomes inactive when
  the pair runtime stops. The application does not unload or delete the driver.
- Keep network PCM at full scale and hardware output devices at 100%. Listening
  volume is applied in CoreAudio's floating-point playback path.
- Use a shared control and health protocol for the GUI, CLI, setup wizard, and
  tests.
- Require no root-owned helper, App Store distribution, or stored remote
  password.
- Make expected disabled states visually distinct from unexpected failures.

## Repository and Process Layout

The three delivery stages remain in one repository:

```text
snapcast-stereo-pair/
├── client/
├── server/
├── common/
├── integration/
├── native/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── StereoPairCore/
│   │   ├── StereoPairAgent/
│   │   ├── MacStereoPair/
│   │   └── mac-stereo-pairctl/
│   ├── Tests/
│   └── Packaging/
├── packaging/
│   └── homebrew/
└── docs/
```

The logical delivery stages are:

1. Runtime control and health protocol.
2. Native SwiftUI application.
3. First-run setup wizard and source/Homebrew packaging.

These are milestones and dependency boundaries, not separate repositories.

## Runtime Architecture

```text
MacStereoPair.app ─┐
                   ├─ Unix Domain Socket ─ StereoPairAgent
mac-stereo-pairctl ┘                         ├─ launchctl
                                             ├─ Snapserver JSON-RPC
                                             └─ shared audio metrics
```

### StereoPairAgent

`StereoPairAgent` is a per-user LaunchAgent. It:

- owns the local control socket;
- reports complete status snapshots and incremental events;
- executes idempotent audio-mode changes;
- invokes fixed runtime helpers with argument arrays, never interpolated shell;
- monitors local launchd services, Snapserver JSON-RPC, and shared audio
  metrics;
- records transition state so a crash can be reconciled;
- attempts best-effort remote actions over SSH;
- produces structured diagnostic events.

The Agent never writes audio samples and never runs as root.

### Splitter Metrics

The splitter publishes a fixed-size POSIX shared-memory record containing:

- a monotonically increasing sequence number;
- monotonic timestamp;
- left and right peak dBFS;
- left and right RMS dBFS;
- clip booleans;
- capture sample rate;
- FIFO write status.

The Agent reads the most recent record and sends meter updates to connected
clients at approximately 20 Hz. No high-frequency metrics are written to disk.

## Control Protocol

The control socket lives under the runtime support directory and is readable
only by the current user (`0600`). The Agent verifies peer credentials before
accepting a connection.

Protocol messages use versioned JSON Lines:

```text
GetSnapshot
Subscribe
SetAudioMode
RestartPair
SetClientVolume
SetClientMute
SetClientLatency
ExportDiagnostics
```

All commands use structured enums and validated values. The Agent:

- returns one complete snapshot after connection;
- streams service, mode, stream, client, and meter events;
- rejects unknown fields that affect safety-critical commands;
- uses request identifiers and explicit success/error results;
- supports one-shot CLI usage and persistent GUI subscriptions.

`mac-stereo-pairctl status --json` returns a machine-readable snapshot.

## Runtime Modes

The top-level audio mode is one of:

```text
snapcast
system
transitioning
```

Overall health is independently one of:

```text
healthy
degraded
failed
disabled
```

### Snapcast Mode

- BlackHole is the source Mac's default output.
- Snapserver, splitter, local Snapclient, pairing, and wake recovery are loaded.
- Both clients report the expected streams.
- Listening volume is applied by CoreAudio at full PCM scale.

### System Mode

The switch performs:

1. Stop local playback output to prevent brief doubled audio.
2. Switch the source Mac to the last non-BlackHole output.
3. Restore that output's saved or normalized hardware state.
4. Stop pairing and wake recovery so they cannot re-enable the runtime.
5. Stop splitter and Snapserver.
6. Best-effort stop the remote client and remote wake recovery using a
   preconfigured SSH key.

The selected output is remembered. If it is unavailable, use the configured
native output device. If local output switching fails, attempt to restart the
previous Snapcast mode and report the failure.

Remote failure never blocks or rolls back the local switch. The UI reports that
the local Mac succeeded while the remote state is not synchronized.

### Transition Persistence

The target mode and completed transition steps are persisted before service
changes begin. After an Agent restart, it either resumes a safe remaining step
or rolls back according to the recorded step. Repeated commands are idempotent.

## Mode Switching and Remote Access

Remote status during normal operation comes from Snapserver:

- remote client connected;
- expected stream;
- volume and mute state;
- last connection change.

Continuous SSH polling is not part of normal monitoring.

SSH is used only for setup validation and best-effort mode changes. SSH calls:

- use the system OpenSSH client;
- use `BatchMode=yes`;
- require a previously confirmed host key;
- use a connection timeout and bounded operation timeout;
- never present a password sheet in the native application.

The first-run wizard may launch Terminal for `ssh-copy-id`, where the user
enters the password outside the native application.

## Health Model

Core monitored units are:

- Snapserver;
- stereo splitter;
- local Snapclient;
- pairing service;
- local wake recovery;
- remote Snapclient;
- remote wake recovery when verifiable.

Health aggregation includes:

- launchd state, PID, run count, and last exit code;
- control API reachability;
- stream presence and format;
- correct left/right routing;
- client connectivity;
- splitter heartbeat freshness;
- FIFO and capture failures;
- AudioQueue invalidation or repeated restart indicators;
- pairing and wake-recovery last success times.

### Grace Periods

- A single failed poll or short network interruption does not create a failure.
- A remote client must remain offline for 5-10 seconds before the pair becomes
  degraded.
- A local KeepAlive service may restart within 2-3 seconds without triggering a
  failure notification.
- Multiple splitter restarts within 30 seconds, or continued restart growth
  over five minutes, indicate a crash loop.
- One initial 200 ms resync after startup or wake is not a failure.
- Services intentionally stopped in system mode use `disabled`, not `failed`.

### Recovery

- The engine continues to use launchd KeepAlive for local process recovery.
- The Agent retries transient snapshots and remote operations.
- The primary UI action is "Restart Pair" or "Reconnect".
- Individual service start/stop remains in Advanced Diagnostics.
- Notification state is debounced and sent once per incident; recovery resets
  the notification state.

### Notifications

The menu-bar application requests notification permission only after the first
successful setup. It sends notifications for state changes rather than every
health sample:

- Snapserver or the local playback path fails in Snapcast mode;
- either client remains offline beyond its grace period;
- left/right routing becomes incorrect;
- splitter or client restart activity indicates a crash loop;
- wake recovery does not complete within 30 seconds;
- a mode transition fails or leaves a partial remote state.

The same incident is not repeated until the affected service recovers. Expected
service stops in system mode never generate failure notifications.

If the main window is closed, notifications continue while the menu-bar
application runs. Quitting the GUI intentionally ends its notifications; the
Agent keeps service and incident state for presentation on the next launch.

## Native Application

### Presentation

The application is a menu-bar application with:

- `MenuBarExtra` for mode, volume, mute, overall status, and quick actions;
- a main window for full channel, routing, synchronization, and health control;
- an activated standard app window when opened from the menu bar;
- no Dock presence during normal menu-bar operation.

Closing the main window does not stop the runtime. Quitting the GUI does not
stop the runtime. Only an explicit audio-mode change stops services.

### Main Console

The approved layout is the dual-channel console:

- mode selector at the top;
- left and right channel modules in the visual center;
- realtime peak/RMS meters with peak hold and clip indication;
- per-channel volume, mute, device, route, and latency;
- central master volume;
- service status bus at the bottom.

The approved status bus uses partitioned instrumentation:

```text
Control | Audio Path | Routing | Recovery
```

Each service uses a discrete LED indicator:

- steady green: healthy;
- slow green pulse: active work or fresh heartbeat;
- amber: degraded or transition warning;
- red: confirmed failure;
- dim gray: intentionally disabled.

Only the LED glows or pulses. Text must not pulse. Color is never the sole
carrier of meaning; icon/text labels accompany every state.

### Volume and Delay

- The master slider adjusts both clients while preserving their relative
  per-side offsets.
- Per-side sliders adjust one client.
- Per-side mute remains available on the main console.
- Per-side latency uses integer milliseconds from 0 through 500, with 1 ms
  steps.
- Values are clamped before being sent to Snapserver.

If the prior client levels are `L` and `R`, moving master from `M0` to `M1`
computes `L + (M1 - M0)` and `R + (M1 - M0)`, clamped to 0 through 100. A
per-side change replaces only that client's level and therefore becomes the new
offset reference for later master changes.

### Main Console Content

The main console includes, without requiring Advanced Settings:

- audio mode;
- overall health;
- left and right realtime meters;
- left and right volume, mute, and latency;
- master volume and master mute;
- left and right client and device identity;
- stream format and stream state;
- synchronization status;
- BlackHole active/inactive state;
- built-in speaker hardware-volume state;
- service health summary;
- reconnect/restart-pair action.

### Advanced Settings

Advanced Settings is limited to:

- logs;
- diagnostic export;
- protocol and runtime versions;
- service paths and individual maintenance actions;
- raw health details.

### Failure Presentation

The main window retains one stable layout in four key states:

1. Healthy Snapcast mode.
2. Mode transition with a step-by-step progress overlay.
3. Degraded mode with one side offline and the other side still playing.
4. System mode with runtime services intentionally disabled.

The transition state locks duplicate mode actions. The degraded state explains
the affected capability and offers a safe recovery action.

## First-Run Setup

The approved wizard uses a persistent step sidebar and a detailed current-step
pane.

Steps:

1. Welcome and audio-path explanation.
2. System dependency checks.
3. Local runtime installation.
4. Remote Mac connection and SSH setup.
5. Verification and completion.

When a step needs a password, administrator action, or interactive Homebrew
authorization, the wizard:

1. generates a fixed-argument setup script;
2. opens Terminal to run it;
3. shows the exact remaining action in the native app;
4. polls for completion;
5. resumes automatically after validation.

The native app does not read local administrator or remote SSH passwords.

If a dependency already exists, the wizard confirms it and skips installation.
Existing `pair.env`, installed services, and SSH configuration are detected and
offered for reuse.

## Languages and Accessibility

Initial languages:

- English;
- Simplified Chinese.

The app follows the system language by default and provides an in-app override.

Accessibility requirements:

- complete keyboard navigation;
- logical focus order;
- VoiceOver labels for meters, LEDs, and mode controls;
- reduced-motion support for pulses;
- sufficient contrast;
- text labels in addition to color;
- system Dynamic Type where practical;
- no control smaller than the macOS pointer target norm.

## Installation and Packaging

Minimum supported macOS version: macOS 14.

Build and install:

- Swift Package targets build with the installed Xcode toolchain;
- the application installs under `~/Applications`;
- the runtime installer installs the runtime LaunchAgents;
- the native installer installs the app, Agent, and `mac-stereo-pairctl`;
- no root helper is installed;
- the app checks runtime and control-protocol compatibility before operating.

The first release:

- builds from source;
- uses local ad-hoc signing;
- is not notarized;
- has no in-app auto-updater;
- documents Gatekeeper behavior;
- supports a future Homebrew build-from-source formula.

## Security and Privacy

- The control socket is local-only and owner-only.
- The Agent validates peer user identity.
- No HTTP control listener is added.
- No arbitrary command path, shell fragment, or environment variable may be
  supplied through the protocol.
- SSH credentials are never stored by the native application.
- Remote host keys must be confirmed during setup.
- Diagnostics export is redacted by default.
- Public logs exclude IP addresses, usernames, home paths, SSH targets, tokens,
  and pairing secrets.
- Full diagnostics require an explicit local user action and are never uploaded.

## Licensing

The native application, Agent, and CLI use GPL-3.0-or-later to match the runtime
repository. Snapcast provenance and third-party notices remain intact.

No third-party Swift runtime dependency is required for the first implementation.

## Testing Strategy

### Unit Tests

- launchd output parsing;
- health aggregation and grace periods;
- mode/health state transitions;
- master/per-side volume derivation;
- latency validation;
- remote-failure degradation;
- notification de-duplication;
- protocol encoding and version checks.

### Integration Tests

- Unix socket request/response and subscription;
- fake launchctl and mode scripts;
- idempotent repeated mode change;
- partial remote failure;
- Agent restart during transition;
- splitter metric shared-memory publication;
- diagnostics redaction.

### UI Tests

- four primary visual states;
- menu-bar commands;
- mode confirmation and disabled transition controls;
- English and Simplified Chinese;
- VoiceOver labels;
- first-run wizard state restoration.

### Hardware Acceptance

- two-Mac mode switch in both directions;
- BlackHole receives no system output in system mode;
- remote success and remote-offline behavior;
- forced service crashes and recovery;
- sleep/wake recovery;
- AudioQueue invalidation;
- correct left/right routes and synchronization;
- realtime meters and clip indication;
- implementation and use with a preconfigured SSH key only.

## Out of Scope

- Replacing the Snapcast audio engine.
- Removing Snapweb in this implementation cycle.
- App Store distribution.
- Paid Developer ID signing and notarization.
- Automatic application updates.
- Multiple simultaneous stereo-pair profiles.
- Room correction or additional audio DSP.
- Individual service management as the primary user workflow.

## Acceptance Criteria

- A user can install from source and complete local and remote setup through the
  wizard with Terminal-assisted authentication.
- The main window shows all modes, channel controls, meters, routing, format,
  synchronization, and health required by this specification.
- Switching to system mode stops BlackHole capture, restores the last output,
  and marks intentionally stopped services as disabled.
- A failed remote stop does not block local recovery and is clearly reported.
- The menu bar and main window report healthy, degraded, failed, disabled, and
  transition states without false alarms from a single transient poll.
- Closing or crashing the GUI does not interrupt audio playback.
- The CLI and GUI obtain the same status through the same protocol.
- No password, private key, token, or pairing secret is stored by the native
  application.
- Automated tests and the two-Mac hardware acceptance suite pass before release.
