# Homebrew Source Build

The repository includes a head-only Homebrew formula:

```text
packaging/homebrew/macbook-stereo-pair.rb
```

It builds from source with the installed Xcode toolchain and Homebrew
dependencies. It is intended for a project tap or direct local installation,
not submission to `homebrew-core`.

## 1. Requirements

- macOS 14 or newer.
- Xcode Command Line Tools and a compatible Swift toolchain.
- Homebrew on Apple Silicon or Intel.
- BlackHole 2ch, which remains a separately installed audio driver.

Install the audio driver:

```sh
brew install --cask blackhole-2ch
```

## 2. Install

From a project tap:

```sh
brew install --HEAD damoqiongqiu/stereo-pair/macbook-stereo-pair
```

For a local checkout before publishing a tap:

```sh
brew install --HEAD ./packaging/homebrew/macbook-stereo-pair.rb
```

The formula builds the Snapcast runtime, splitter helpers, Swift control Agent,
CLI, and native app. It installs the app under the Homebrew prefix and installs
the source/runtime support under `share/macbook-stereo-pair`.

Copy the app to the user Applications directory:

```sh
cp -R "$(brew --prefix)/opt/macbook-stereo-pair/MacBook Stereo Pair.app" \
  "$HOME/Applications/"
```

Launch it and complete the setup wizard. The wizard accepts the Homebrew prefix
on both Apple Silicon and Intel:

```text
/opt/homebrew
/usr/local
```

## 3. Signing and Gatekeeper

Public source builds are ad-hoc signed and are not notarized. They do not require
a paid Apple Developer ID and have no App Store component.

If Gatekeeper blocks a downloaded build, verify that the source came from the
project repository. The supported source-build path does not require disabling
Gatekeeper, SIP, or another macOS security feature. Users choosing a different
distribution method are responsible for the signing decision.

## 4. Updating and Removal

Because the formula tracks the `main` branch:

```sh
brew update
brew reinstall --HEAD macbook-stereo-pair
```

After updating the Homebrew package, launch the newly copied app and use the
normal product installer if an upgrade is reported. If detection is incorrect
or you intentionally want a complete rebuild, use Advanced Diagnostics →
Installation maintenance → Force reinstall current version. The force path
keeps user configuration.

Return to system audio before removal:

```sh
~/Library/Application\ Support/Snapcast/set-mode.sh native
```

Then remove the native interface:

```sh
"$(brew --prefix)/opt/macbook-stereo-pair/share/macbook-stereo-pair/integration/scripts/uninstall-native.sh"
brew uninstall macbook-stereo-pair
```

`uninstall-native.sh` removes the app, control Agent, and CLI while preserving
the audio runtime, user configuration, logs, and remote control state. To stop
the local runtime first, run the corresponding installed `uninstall-local.sh`
from the same `share/macbook-stereo-pair/integration/scripts/` directory.
Complete file removal is documented in
[installation.md](installation.md#8-complete-removal).
