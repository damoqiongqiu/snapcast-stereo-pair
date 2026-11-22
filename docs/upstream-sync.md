# Upstream Synchronization

The public runtime keeps the upstream Snapcast history and adds a macOS
stereo-pair integration layer on top of a release tag. Upstream remotes are:

```text
upstream https://github.com/snapcast/snapcast.git
origin   https://github.com/damoqiongqiu/snapcast-stereo-pair.git
```

## Check the Current Bases

```sh
git remote -v
git merge-base --is-ancestor v0.35.0 HEAD
git log --oneline --decorate --graph -12
```

The first public integration base is Snapcast `v0.35.0`.

## Rebase the Project Layer

Fetch upstream tags and replay the project commit onto the desired release:

```sh
git fetch upstream --tags
git switch main
git switch -c upgrade/snapcast-vX.Y.Z
git rebase --onto vX.Y.Z v0.35.0
```

Resolve conflicts by preserving the project behavior described in
[architecture.md](architecture.md):

- CoreAudio output device selection through `SNAPCLIENT_COREAUDIO_DEVICE`.
- Mono input expansion to a two-channel AudioQueue output.
- Floating-point listening volume through `AudioQueueSetParameter` while PCM
  chunks remain at full scale.
- 20 ms CoreAudio buffering.
- Initialized CoreAudio watchdog timing.
- Process/pipe jitter tolerance and timeline preservation.
- Deferred AudioQueue disposal outside its callback.
- Source and remote wake-recovery services.
- PortAudio BlackHole capture and dual mono FIFOs.
- Normalization of both `vmvc` and `volm` hardware controls.
- Role-based stream routing.
- Native Swift UI, control Agent, Unix socket protocol, and launchd health.
- Shared-memory peak/RMS meters and mirrored player-style waveform history.
- Dual audio modes with remote best-effort synchronization.

When the upstream base tag changes, update this document, the README
compatibility table, and CI expectations together.

## Regenerate the Integration Patch

After the rebased tree passes validation, regenerate the distributable diff:

```sh
git diff --binary vX.Y.Z -- . \
  ':(exclude)integration/patches/snapcast-macos-stereo.patch' \
  ':(exclude)docs/superpowers/**' \
  > integration/patches/snapcast-macos-stereo.patch
git apply --check --reverse integration/patches/snapcast-macos-stereo.patch
```

The reverse check confirms that the patch describes changes already present in
the working tree. On a default case-insensitive macOS filesystem, the upstream
case-only renames `changelog.md` and `.github/pull_request_template.md` can make
the reverse check ambiguous. Exclude those paths when validating on such a
checkout, or run the full reverse check in a case-sensitive checkout:

```sh
git apply --check --reverse \
  --exclude=changelog.md \
  --exclude=.github/pull_request_template.md \
  integration/patches/snapcast-macos-stereo.patch
```

## Validate the Upgrade

```sh
./integration/scripts/build-macos.sh
swift test --package-path native
swift build --package-path native -c release
integration/test/test-pair-config.sh
integration/test/test-audio-levels.sh
integration/test/test-pair-routing.sh
integration/test/test-wake-recovery.sh
integration/test/test-control-plane.sh
integration/test/test-mode-transitions.sh
integration/test/test-control-agent-install.sh
integration/test/test-native-app-packaging.sh
integration/test/test-homebrew-formula.sh
zsh -n integration/scripts/*.sh integration/test/*.sh
plutil -lint integration/launchagents/*.plist.in
./scripts/check-public-tree.sh
```

Build and run upstream unit tests:

```sh
cmake -S . -B .build-tests -G Ninja -DBUILD_SERVER=OFF -DBUILD_CLIENT=ON \
  -DBUILD_TESTS=ON -DBUILD_WITH_SSL=OFF -DBUILD_SHARED_LIBS=OFF
cmake --build .build-tests
./bin/snapcast_test --reporter compact
```

Hardware acceptance still requires the two-MacBook setup. Verify both stream
formats, routing, full-scale PCM with CoreAudio queue volume, `vmvc`/`volm`
normalization, sleep/wake recovery, click-marker alignment, native-mode
restoration, native console and CLI state agreement, notification deduplication,
and remote-offline degradation before merging.

## Privacy

Local `pair.env` files, generated LaunchAgents, logs, build products, private IP
addresses, usernames, credentials, and home paths must never enter a commit.
Keep local configuration under `~/.config/snapcast-stereo-pair/` and run the
public-tree scanner before publication.

