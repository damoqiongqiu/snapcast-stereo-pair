# Upstream Synchronization

The public runtime keeps the upstream Snapcast history and adds one macOS
stereo-pair integration commit on top of a release tag. Upstream remotes are:

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

The first public integration base is Snapcast `v0.35.0`. The companion
controller uses Snapweb `v0.9.3`.

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
- 20 ms CoreAudio buffering.
- Initialized CoreAudio watchdog timing.
- Process/pipe jitter tolerance and timeline preservation.
- PortAudio BlackHole capture and dual mono FIFOs.
- Role-based stream routing.

When the upstream base tag changes, update this document, the README
compatibility table, and CI expectations together.

## Regenerate the Integration Patch

After the rebased tree passes validation, regenerate the distributable diff:

```sh
git diff vX.Y.Z -- . \
  ':(exclude)integration/patches/snapcast-macos-stereo.patch' \
  ':(exclude)docs/superpowers/**' \
  > integration/patches/snapcast-macos-stereo.patch
git apply --check --reverse integration/patches/snapcast-macos-stereo.patch
```

The reverse check confirms that the patch describes changes already present in
the working tree.

## Validate the Upgrade

```sh
./integration/scripts/build-macos.sh
integration/test/test-pair-config.sh
integration/test/test-pair-routing.sh
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
formats, routing, mute/volume behavior, click-marker alignment, native-mode
restoration, and controller compatibility before merging.

## Privacy

Local `pair.env` files, generated LaunchAgents, logs, build products, private IP
addresses, usernames, credentials, and home paths must never enter a commit.
Keep local configuration under `~/.config/snapcast-stereo-pair/` and run the
public-tree scanner before publication.

