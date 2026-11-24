# Repository Instructions

This repository is the macOS audio runtime and owns the native control console.

The runtime owns audio capture, `LeftAudio` and `RightAudio`, Snapserver,
Snapclients, launchd services, the native control Agent, installation, routing,
and device recovery. The native console is not an audio engine.

## Structure

- `client/`: patched Snapclient CoreAudio output.
- `server/`: Snapserver sources.
- `integration/capture/`: BlackHole capture and stereo split.
- `integration/config/`: public configuration example and templates.
- `integration/launchagents/`: rendered per-user service templates.
- `integration/scripts/`: install, routing, mode, health, and maintenance.
- `integration/test/`: configuration, routing, volume, and wake-recovery tests.
- `native/`: Swift control models, Agent, CLI, native SwiftUI console, setup,
  packaging, and tests.
- `docs/`: public architecture, installation, security, and maintenance docs.

## Documentation Map

- `README.md`: public overview, quick start, physical placement, operations, FAQ,
  and documentation index.
- `docs/installation.md`: end-to-end installation, validation, and removal.
- `docs/architecture.md`: capture, synchronization, routing, recovery, and
  acoustic limits.
- `docs/native-console.md`: native app behavior, volume handling, diagnostics,
  accessibility, and packaging.
- `docs/troubleshooting.md`: user-facing recovery procedures.
- `docs/homebrew.md`: source formula installation and removal.
- `docs/hardware-acceptance.md`: two-Mac release acceptance format.
- `docs/upstream-sync.md`: Snapcast rebase and integration-patch workflow.

Keep this file as the canonical source for the complete release-check list.
Other documents should link here instead of duplicating the full checklist.

## Required Checks

Run the checks that cover the change; run the complete set before release:

```sh
./integration/scripts/build-macos.sh
swift test --package-path native
swift build --package-path native -c release
integration/test/test-pair-config.sh
integration/test/test-audio-levels.sh
integration/test/test-audio-profile.sh
integration/test/test-fifo-resilience.sh
integration/test/test-health-check.sh
integration/test/test-pair-routing.sh
integration/test/test-public-tree-privacy.sh
integration/test/test-watchdog-recovery.sh
integration/test/test-wake-recovery.sh
integration/test/test-control-plane.sh
integration/test/test-deployment-target.sh
integration/test/test-mode-transitions.sh
integration/test/test-install-lifecycle.sh
integration/test/test-control-agent-install.sh
integration/test/test-native-app-packaging.sh
integration/test/test-homebrew-formula.sh
integration/test/test-native-release.sh --automated-only
integration/scripts/check-deployment-target.sh
zsh -n integration/scripts/*.sh integration/test/*.sh
plutil -lint integration/launchagents/*.plist.in
./scripts/check-public-tree.sh
```

For upstream unit tests, build `.build-tests` and run:

```sh
./bin/snapcast_test --reporter compact
```

Hardware validation requires two Macs. Document the model, CPU architecture,
macOS and BlackHole versions when changing audio behavior.

## Configuration Rules

- Read pairing values only through `integration/scripts/pair-config.sh`.
- Keep environment overrides authoritative.
- Never execute a user-editable `pair.env` as shell source.
- Derive roles from `LOCAL_CLIENT_ID`, `REMOTE_CLIENT_ID`, and
  `LEFT_IS_REMOTE`; do not bind logic to IP addresses.
- Render account-specific paths and device UIDs from templates at install time.
- Keep configuration compatible with Intel and Apple Silicon Homebrew prefixes.

## Audio Rules

- Preserve one shared capture clock for both mono streams.
- Document that two Macs should be placed symmetrically around the primary
  listener; synchronization does not correct path-length or room asymmetry.
- Keep `LeftAudio` and `RightAudio` at the same sample rate, format, chunk size,
  and buffer unless a reviewed design changes both sides.
- Keep the local Snapclient explicitly bound to a real output device while
  system output is BlackHole.
- Keep BlackHole, the local built-in speaker, and the remote output device at
  100% hardware volume; use Snapcast volume for normal listening.
- Keep both CoreAudio main-volume controls (`vmvc` and `volm`) normalized when
  the device exposes them.
- Before entering Snapcast mode, persist the current physical output UID and
  exact volume. Restore that profile on both Macs before switching back to
  system audio; never default a hand-back path to 100%.
- Apply CoreAudio listening volume through `AudioQueueSetParameter`; do not
  attenuate the integer PCM buffer during software-mixer operation.
- Recreate capture and playback queues after wake; never dispose an AudioQueue
  from one of its own callbacks.
- Preserve timeline continuity for scheduling jitter below the discontinuity
  threshold.
- Do not add lossy codecs or resampling to the default path without measured
  quality and latency evidence.

## Safety and Privacy

- Never commit `pair.env`, IP addresses, usernames, logs, credentials, private
  keys, tokens, or home-directory paths.
- Keep HTTP and TCP control bound to localhost.
- Document that stream port `1704` requires a trusted LAN or VPN/firewall.
- Never disable Gatekeeper, SIP, or another macOS security feature.
- Do not modify a user's live services while running a read-only investigation.
- Do not publish unsigned app bundles or binaries.
- Public releases use ad-hoc signing and no paid Developer ID, App Store, root
  helper, or automatic updater.
- Native control uses an owner-only Unix socket with peer UID validation and
  fixed commands; never accept executable paths or shell fragments.
- Redact diagnostics by default and never upload them automatically.
- Document required macOS privacy permissions and their recovery steps without
  telling users to disable security features.
- Repeated installs are manifest-driven: verified same-version installs are
  no-ops, missing or changed files are repaired, upgrades are allowed, and
  accidental downgrades fail.
- Always keep an explicit user-facing force-reinstall override. It replaces all
  program and service files but preserves pair configuration, remote control
  state, logs, and user preferences.
- Clearing user configuration is a separate destructive operation and must not
  be folded into force reinstall.

## Licensing

Preserve GPL-3.0-or-later notices, upstream copyright headers, and Snapcast
provenance. Record material third-party dependencies in `NOTICE.md`. This is an
unofficial fork and must not be described as an official Snapcast release.

