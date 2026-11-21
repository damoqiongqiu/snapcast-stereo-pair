# Changelog

## Unreleased

- Add a native SwiftUI menu-bar console and dual-channel professional control
  surface with live mirrored waveforms, peak/RMS meters, clip indication,
  master/side volume, mute, latency, routing, stream format, and recovery state.
- Add an owner-only Unix-socket control Agent shared by the native app and
  `mac-stereo-pairctl`, with peer UID validation and launchd-independent audio.
- Add explicit stereo-pair and Mac-system-audio modes, including best-effort
  remote mode synchronization through a fixed SSH helper.
- Add debounced, deduplicated notifications for service failure, client outage,
  routing faults, and wake recovery.
- Add English and Simplified Chinese resources with an in-app language override.
- Add an advanced diagnostics sheet with logs, service maintenance, versions,
  raw snapshots, and redacted diagnostic export.
- Add a resumable first-run wizard with dependency probes and Terminal handoff;
  the app never reads local administrator or remote SSH passwords.
- Add native app packaging, ad-hoc signing, source Homebrew packaging, and
  expanded release checks.
- Normalize BlackHole, local speaker, and remote speaker hardware volumes to
  100% independently of the selected macOS output device.
- Write and verify both virtual and physical CoreAudio main-volume controls.
- Add CoreAudio volume diagnostics and prevent pre-capture attenuation from
  making Snapcast volume appear quieter than native playback.
- Defer CoreAudio queue disposal until after its callback returns, and recreate
  queues when the timeline is invalidated.
- Add source and remote wake-recovery LaunchAgents that restore routing,
  hardware volume, capture, and playback after sleep.
- Apply CoreAudio listening volume through the AudioQueue floating-point volume
  parameter so network PCM remains at full scale.

## v0.1.0 - 2026-11-20

First public source release.

- Two-MacBook left/right channel split.
- 48 kHz / 24-bit mono PCM streams with synchronized playback.
- 20 ms chunks and 200 ms stream buffer.
- BlackHole capture through PortAudio with no additional capture processing.
- Generic role-based configuration and rendered launchd templates.
- Intel and Apple Silicon Homebrew path support.
- Bilingual English/Simplified Chinese controller integration.
- Responsive full-width controller interface.
- Runtime health checks, stream-based routing, native-mode recovery, and
  public-tree validation.

Upstream base: Snapcast `v0.35.0`.
