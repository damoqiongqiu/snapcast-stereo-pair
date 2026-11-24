# Installation

This guide assumes the repository that captures audio is called the source Mac
and the second MacBook is called the remote Mac. Both can use any stable role
names and either can be on the physical left.

Before installation, place both Macs symmetrically around the primary listening
position. See [Physical Placement](../README.md#32-physical-placement) for the
practical layout guidance.

## 1. Prerequisites

Install Xcode Command Line Tools and Homebrew on the source Mac:

```sh
xcode-select --install
```

Install the runtime dependencies:

```sh
brew install --cask blackhole-2ch
brew install switchaudio-osx portaudio cmake ninja pkgconf boost openssl@4 \
  flac libogg libsoxr libvorbis opus
```

The included remote installer copies a locally built Snapclient binary, so both
Macs should use the same CPU architecture. If they differ, build Snapclient on
the remote Mac's architecture and adapt the copy step instead of using the
prebuilt source-Mac binary.

Configure SSH key authentication before remote installation:

```sh
ssh <ssh-user>@<remote-mac-address>
```

The installer uses normal SSH configuration and does not prompt for or store a
password.

## 2. Clone the Repository

```sh
git clone https://github.com/damoqiongqiu/snapcast-stereo-pair.git
cd snapcast-stereo-pair
```

## 3. Configure Roles

Run the interactive configurator:

```sh
./integration/scripts/configure-pair.sh
```

Defaults and file values are documented in
[`integration/config/pair.env.example`](../integration/config/pair.env.example).
The resulting file is stored outside the repository:

```text
~/.config/snapcast-stereo-pair/pair.env
```

The relevant values are:

```sh
CONFIG_SCHEMA=1
REMOTE_USER="<ssh-user>"
REMOTE_HOST="<remote-mac-address>"
SOURCE_HOST=""
LEFT_IS_REMOTE=true
CAPTURE_DEVICE="BlackHole 2ch"
CAPTURE_DEVICE_UID="BlackHole2ch_UID"
LOCAL_OUTPUT_DEVICE="BuiltInSpeakerDevice"
NATIVE_OUTPUT_DEVICE_UID="BuiltInSpeakerDevice"
REMOTE_OUTPUT_DEVICE_UID="BuiltInSpeakerDevice"
LOCAL_CLIENT_ID="stereo-local"
REMOTE_CLIENT_ID="stereo-remote"
```

Use `SOURCE_HOST=""` to detect the primary IPv4 address when configuring. Set it
explicitly if the source Mac has multiple active interfaces.

List CoreAudio outputs and their UIDs when choosing the local and native output
devices:

```sh
SwitchAudioSource -a -t output
```

`CAPTURE_DEVICE_UID` is normalized to 100% before capture.
`LOCAL_OUTPUT_DEVICE` selects and normalizes the source Mac's physical output.
`REMOTE_OUTPUT_DEVICE_UID` performs the same step on the remote Mac.
`NATIVE_OUTPUT_DEVICE_UID` is restored and normalized by native mode. The three
output fields default to the built-in speaker.

Environment variables override file values for automation:

```sh
PAIR_NONINTERACTIVE=1 \
REMOTE_USER=tester \
REMOTE_HOST=remote.local \
SOURCE_HOST=192.0.2.10 \
LEFT_IS_REMOTE=true \
./integration/scripts/configure-pair.sh --print
```

`--print` resolves and displays the configuration without writing it. The
address above is reserved for documentation and is not a real network target.

## 4. Build and Install the Local Product

Build and validate without changing services:

```sh
./integration/scripts/build-macos.sh
integration/test/test-pair-config.sh
integration/test/test-audio-levels.sh
integration/test/test-pair-routing.sh
integration/test/test-wake-recovery.sh
```

Install or upgrade the complete local product:

```sh
./integration/scripts/install-product.sh
```

The installer:

- reads `state/installation.json` when present;
- skips verified repeat installation or repairs missing files;
- treats a different installed version as an upgrade;
- rejects an accidental downgrade unless force reinstall is requested;
- treats changed pairing or remote-control configuration as a repair so
  rendered services are refreshed;
- renders the local and remote speaker UIDs and physical side into
  `state/audio-devices.json` for read-only system-volume monitoring;
- renders templates into `~/Library/Application Support/Snapcast/`;
- keeps BlackHole and the built-in speaker at 100% hardware volume;
- creates the left/right FIFOs;
- installs the native app, control Agent, CLI, and local LaunchAgents;
- switches system output to BlackHole;
- starts Snapserver, splitter, local Snapclient, route, pairing, and wake
  recovery services.

Inspect the decision without changing files or services:

```sh
./integration/scripts/install-product.sh --dry-run
```

Force a clean rebuild of the current version:

```sh
./integration/scripts/install-product.sh --force-reinstall
```

Force reinstall replaces the application, Agent, CLI, audio runtime, scripts,
LaunchAgents, and templates. It preserves the pairing configuration, remote
control configuration, logs, and user preferences. It may briefly interrupt
audio while runtime services restart.

## 5. Install the Remote Client

Run from the source Mac after local installation:

```sh
./integration/scripts/install-remote.sh
```

This command resolves the remote home directory, renders the LaunchAgents for
that account, copies Snapclient and the wake listener, and bootstraps
`com.snapcast.remote-client` and `com.snapcast.remote-wake-recovery`.

It also installs a fixed remote mode helper and writes the local non-secret
remote control configuration:

```text
~/Library/Application Support/Snapcast/state/remote-control.json
```

That file contains the remote user, host, rendered mode-helper path, and the
fixed path to the read-only volume helper, with mode `0600`. It never contains a
password, private key, or token. Remote mode commands run with `BatchMode=yes`
and a bounded timeout. Failure to stop or start the remote client degrades
synchronization status but does not roll back the local mode change.

## 6. Native Console and First-Run Setup

The local product installation installs the app under `~/Applications`.
Its first-run wizard can also run
the local and remote installation steps through Terminal. It detects existing
configuration and preconfigured SSH keys. Password entry stays in Terminal.

The app requires macOS 13 or newer. It is ad-hoc signed, not notarized, and does
not require an Apple Developer subscription. See
[native-console.md](native-console.md).

The native app also exposes **Advanced Diagnostics → Installation maintenance**
with a confirmed force-reinstall action. This exists because file and version
detection can occasionally be wrong; the user must retain an explicit override.

## 7. Permissions and First-Run Prompts

Allow only the macOS capabilities that the product actually uses:

- **Microphone/audio input** on the source Mac for
  `snapcast-capture-blackhole`, which reads the virtual BlackHole input.
- **Notifications** for the native app when service and channel alerts are
  wanted.
- **Local Network** and **Firewall** access for the two Macs on the same trusted
  LAN or VPN.
- **Remote Login** and key-only SSH on the remote Mac.

macOS may not show every request from a background LaunchAgent. If the app
blocks, streams stay `idle`, or waveforms remain flat after an install or
force reinstall, check
[Permission and Privacy Checks](troubleshooting.md#1-permission-and-privacy-checks)
instead of repeatedly reinstalling.

Accessibility, Screen Recording, Full Disk Access, Input Monitoring, and
Developer Tools permissions are not required. Do not disable Gatekeeper or SIP.

## 8. Validate

Run:

```sh
./integration/scripts/check-health.sh
```

Expected conditions:

- `LeftAudio` and `RightAudio` both report `48000:24:1`.
- Capture and local output hardware volumes both report `100.00%`.
- `LeftAudio` lists the client role mapped to physical left.
- `RightAudio` lists the client role mapped to physical right.
- No recent `Not enough`, `age >`, `No chunk available`, or `onResync` warnings
  appear in the local logs.
- The native console shows two connected channels, fresh Splitter activity,
  correct routes, and a healthy recovery zone.

Before switching modes, verify the saved native profile exists on both Macs.
System mode restores the remembered physical output and exact volume, with a
30% built-in-speaker fallback when that output is unavailable.

The native app and CLI use the same Agent snapshot:

```sh
~/Library/Application\ Support/Snapcast/bin/mac-stereo-pairctl status
```

Advanced Diagnostics exports redacted information only after an explicit local
action. Review any diagnostic file before sharing it.

While BlackHole is the active macOS output, its volume slider controls the
capture level rather than the built-in speakers. Use the native console volume
for listening; the runtime normalizes both hardware stages to avoid double
attenuation.

CoreAudio applies the console volume through the AudioQueue floating-point
volume parameter. The 24-bit PCM received from Snapserver remains at full scale,
so changing listening volume does not rewrite the integer audio buffer.

## 9. Complete Removal

Return the source Mac to native audio first:

```sh
~/Library/Application\ Support/Snapcast/set-mode.sh native
```

For a coordinated, best-effort remote transition, use the native console or
`mac-stereo-pairctl stop` instead. The generated `set-mode.sh` changes only the
local Mac.

Stop all local services and restore normal output:

```sh
./integration/scripts/uninstall-local.sh
```

Remove the native app, control Agent, and CLI:

```sh
./integration/scripts/uninstall-native.sh
```

`uninstall-local.sh` preserves runtime files. A complete removal additionally
requires deleting these generated local paths after confirming them:

```text
~/Library/Application Support/Snapcast
~/Library/Logs/Snapcast
~/Library/LaunchAgents/com.snapcast.*.plist
```

The remote installer has no automatic uninstaller. On the remote Mac, boot out
`com.snapcast.remote-client` and `com.snapcast.remote-wake-recovery`, then remove
the copied binaries, scripts, LaunchAgents, and the `.snapcast-remote-mode` and
`.snapcast-volume` symlinks after confirming the account and paths. On the source
Mac, separately remove `~/Library/Application Support/Snapcast/state/remote-control.json`
if remote mode control is no longer needed.

