# Changelog

## Unreleased

- Consolidate and renumber the public documentation set, add symmetric physical
  placement guidance, correct native menu and removal behavior, reduce duplicated
  release checklists, and expand the README and `llms.txt` document maps.
- Add a native SwiftUI menu-bar console and dual-channel professional control
  surface with live mirrored waveforms, peak/RMS meters, clip indication,
  master/side volume, mute, latency, routing, stream format, and recovery state.
- Add a responsive, bounded console window, single-instance protection, direct
  volume-slider feedback with 5% reference ticks, and separate read-only
  physical system-volume indicators for both Macs.
- Tighten the console dashboard by grouping mute and delay controls, reducing
  secondary card spacing, unifying the system-volume refresh control, improving
  status legibility, and reducing the no-scroll minimum window size to 1040 × 660.
- Redraw the channel waveforms as stable audio instruments with separate Peak
  and RMS envelopes, dB reference grids, live dBFS readouts, and clipping-aware
  color instead of decorative time-based motion.
- Make waveform levels follow per-channel Snapcast volume and mute state, move
  the Peak/RMS readout into the channel title row, and use green-to-amber-to-red
  peak coloring as levels approach full scale.
- Make Snapcast volume sliders track continuously at pointer resolution while
  serializing throttled audio previews, coalescing click updates, and committing
  the final rounded percentage after release. Periodic status updates pause
  during an active drag to keep interaction responsive.
- Force fresh Snapserver JSON-RPC connections so paired master-volume writes
  cannot lose one side to an empty reused keep-alive response.
- Remove the unnecessary trailing divider after the final status-card zone.
- Limit the in-app language menu to the shipped English and Simplified Chinese
  resources, with legacy “follow system” preferences falling back to English.
- Remove main-console scrolling and require the full dashboard to fit at the
  minimum window size.
- Align the volume handle, track endpoints, and scale marks to one shared
  geometry while preserving native slider accessibility semantics and keeping
  keyboard focus styling out of pointer drags.
- Show the native console in the Dock with a bundled app icon, while retaining
  its menu-bar controls.
- Refresh the README and public documentation around the native console,
  including current English and Simplified Chinese screenshots, a clearer
  fork comparison, agent-oriented references, FAQ content, and `llms.txt`.
- Remove obsolete upstream TODO, roadmap, and generic packaging workflow
  material, and align issue and pull request templates with the native product
  model.
- Add an owner-only Unix-socket control Agent shared by the native app and
  `mac-stereo-pairctl`, with peer UID validation and launchd-independent audio.
- Add explicit stereo-pair and Mac-system-audio modes, including best-effort
  remote mode synchronization through a fixed SSH helper.
- Add debounced, deduplicated notifications for service failure, client outage,
  routing faults, and wake recovery.
- Treat a recently successful periodic automatic-pairing check as healthy
  between launchd invocations instead of displaying a persistent warning.
- Ignore out-of-order status responses so releasing a volume slider does not
  briefly restore the previous value before showing the committed volume.
- Add English and Simplified Chinese resources with English as the default and
  an in-app language override.
- Add an advanced diagnostics sheet with logs, service maintenance, versions,
  raw snapshots, and redacted diagnostic export.
- Add a resumable first-run wizard with dependency probes and Terminal handoff;
  the app never reads local administrator or remote SSH passwords.
- Add native app packaging, ad-hoc signing, source Homebrew packaging, and
  expanded release checks.
- Add manifest-driven repeat installation, repair, upgrade detection, explicit
  downgrade rejection, installation locking, and configuration schema checks.
- Add a user-visible force-reinstall path that rebuilds all program and service
  files while preserving pair configuration, logs, and preferences.
- Preserve each Mac's physical output device and exact volume when entering
  Snapcast mode, and restore that profile before handing audio back to macOS.
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
- Keep the control Agent accepting requests after transient socket errors, and
  release command-process pipes so long-running health monitoring does not
  exhaust file descriptors.

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
