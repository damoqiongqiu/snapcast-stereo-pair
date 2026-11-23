# Hardware Acceptance

Native release acceptance requires both MacBooks online. Record the environment
and keep the completed report outside the public repository.

Recommended environment variables:

```sh
SNAPCAST_HARDWARE_ACCEPTANCE_FILE=/path/to/private/hardware-report.md \
  ./integration/test/test-native-release.sh
```

## Required Report Sections

Use the exact headings below. They are intentionally unnumbered so reports from
different releases can be compared mechanically. Add observations and evidence
under each heading.

```markdown
## Mac models and operating systems
## Stereo-pair mode
## System mode
## Remote offline
## Sleep and wake
## Crash recovery
## Meters and synchronization
## Localization and accessibility
## Diagnostics privacy
```

## Mac models and operating systems

- Record both Mac models, CPU architectures, macOS versions, BlackHole versions,
  PortAudio versions, and Swift/Xcode versions.
- Record whether placement is symmetric, the approximate listener distance,
  orientation, and whether either Mac is near a wall, corner, or reflective
  surface.
- Record whether the pair uses Apple Silicon or Intel Homebrew paths.

## Stereo-pair mode

- Confirm `LeftAudio` and `RightAudio` both report `48000:24:1`.
- Confirm the correct client is connected to each stream.
- Confirm both hardware volumes are 100%.
- Confirm playback is synchronized and the app, menu bar, and CLI agree.

## System mode

- Confirm the local output leaves BlackHole and returns to the saved physical
  output.
- Confirm local services are disabled rather than reported as failed.
- Confirm the remote mode is attempted with key-only SSH.
- Confirm the app can return to stereo-pair mode.

## Remote offline

- Stop or disconnect the remote Mac.
- Confirm within six seconds that the remote channel turns red, its waveform
  clears, and the overall health becomes degraded.
- Confirm local system-audio recovery still completes.
- Confirm one degradation warning appears and is not repeated continuously.
- Reconnect and confirm the incident resets.

## Sleep and wake

- Sleep both Macs, wake them, and confirm routing, hardware volume, capture, and
  playback recover.
- Confirm a wake slower than 30 seconds raises at most one incident.

## Crash recovery

- Force each KeepAlive service to exit.
- Confirm launchd restarts it and transient restarts do not notify.
- Confirm a crash loop or persistent failure notifies once.

## Meters and synchronization

- Use speech and familiar stereo music with centered vocals and hard-panned
  instruments.
- Confirm both waveforms move independently and the center image remains in
  front of the listener.
- Confirm the two Macs are symmetrically placed and the listener is centered
  between them; otherwise record the asymmetry as part of the result.
- Confirm no repeated resynchronization, crackle, dropout, or channel swap.

## Localization and accessibility

- Verify English and Simplified Chinese at common window sizes.
- Verify keyboard navigation and VoiceOver labels for controls, LEDs, meters,
  and mode selection.
- Enable Reduce Motion and confirm LED pulses stop while status stays legible.

## Diagnostics privacy

- Generate a redacted export.
- Confirm it contains no IP address, username, home path, SSH target, token, or
  pairing secret.
- Confirm the app did not upload the file.
