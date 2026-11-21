# Changelog

## Unreleased

- Normalize BlackHole, local speaker, and remote speaker hardware volumes to
  100% independently of the selected macOS output device.
- Write and verify both virtual and physical CoreAudio main-volume controls.
- Add CoreAudio volume diagnostics and prevent pre-capture attenuation from
  making Snapcast volume appear quieter than native playback.
- Defer CoreAudio queue disposal until after its callback returns, and recreate
  queues when the timeline is invalidated.
- Add source and remote wake-recovery LaunchAgents that restore routing,
  hardware volume, capture, and playback after sleep.

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
