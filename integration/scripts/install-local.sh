#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
support_dir="$HOME/Library/Application Support/Snapcast"
log_dir="$HOME/Library/Logs/Snapcast"
launch_dir="$HOME/Library/LaunchAgents"
run_dir="$support_dir/run"
uid="$(id -u)"

source "$repo_root/integration/scripts/pair-config.sh"
source "$repo_root/integration/scripts/audio-profile.sh"
load_pair_config
if [[ "${PAIR_LOCAL_ONLY:-0}" == "1" ]]; then
  prepare_local_only_config
fi
require_pair_config
compute_pair_roles

"$repo_root/integration/scripts/build-macos.sh"
"$repo_root/native/Packaging/build-native.sh"
homebrew_bin="$(brew --prefix)/bin"

mkdir -p "$support_dir/bin" "$support_dir/data" "$log_dir" "$launch_dir" "$run_dir"
for name in left right; do
  fifo="$run_dir/$name.pcm"
  if [[ ! -p "$fifo" ]]; then
    mkfifo "$fifo"
  fi
  chmod 600 "$fifo"
done

install -m 755 "$repo_root/.build/bin/snapserver" "$support_dir/bin/snapserver"
install -m 755 "$repo_root/.build/bin/snapclient" "$support_dir/bin/snapclient"
install -m 755 "$repo_root/.build/bin/set-audio-volume" "$support_dir/bin/set-audio-volume"
install -m 755 "$repo_root/.build/bin/wake-recovery-listener" "$support_dir/bin/wake-recovery-listener"
install -m 755 "$repo_root/native/.build/release/StereoPairAgent" "$support_dir/bin/StereoPairAgent"
install -m 755 "$repo_root/native/.build/release/mac-stereo-pairctl" "$support_dir/bin/mac-stereo-pairctl"
install -m 755 "$repo_root/.build/bin/capture-blackhole" "$homebrew_bin/snapcast-capture-blackhole"
install -m 644 "$repo_root/integration/capture/capture-blackhole-pa.c" "$support_dir/capture-blackhole-pa.c"
render_pair_template \
  "$repo_root/integration/config/snapserver.conf.in" \
  "$support_dir/snapserver.conf"

for name in server local-client route splitter pairing wake-recovery control-agent; do
  render_pair_template \
    "$repo_root/integration/launchagents/$name.plist.in" \
    "$launch_dir/com.snapcast.$name.plist"
done

render_pair_template \
  "$repo_root/integration/scripts/set-mode.sh" \
  "$support_dir/set-mode.sh"
chmod 755 "$support_dir/set-mode.sh"
render_pair_template \
  "$repo_root/integration/scripts/ensure-pair-routing.sh" \
  "$support_dir/ensure-pair-routing.sh"
chmod 755 "$support_dir/ensure-pair-routing.sh"
render_pair_template \
  "$repo_root/integration/scripts/audio-levels.sh" \
  "$support_dir/audio-levels.sh"
chmod 644 "$support_dir/audio-levels.sh"
install -m 755 "$repo_root/integration/scripts/health-marker.sh" "$support_dir/health-marker.sh"
install -m 755 "$repo_root/integration/scripts/audio-profile.sh" "$support_dir/audio-profile.sh"
render_pair_template \
  "$repo_root/integration/scripts/route-audio.sh" \
  "$support_dir/route-audio.sh"
chmod 755 "$support_dir/route-audio.sh"
render_pair_template \
  "$repo_root/integration/scripts/wake-recovery-local.sh" \
  "$support_dir/wake-recovery-local.sh"
chmod 755 "$support_dir/wake-recovery-local.sh"

audio_save_native_profile \
  "$support_dir/state" \
  "$CAPTURE_DEVICE_UID" \
  SwitchAudioSource \
  "$support_dir/bin/set-audio-volume"

for label in com.snapcast.local-client com.snapcast.capture com.snapcast.server com.snapcast.route com.snapcast.splitter com.snapcast.pairing com.snapcast.wake-recovery com.snapcast.control-agent; do
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
done
for label in com.snapcast.server com.snapcast.route com.snapcast.splitter com.snapcast.local-client com.snapcast.pairing com.snapcast.wake-recovery com.snapcast.control-agent; do
  launchctl enable "gui/$uid/$label" 2>/dev/null || true
done
sleep 1

launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.route.plist"
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.server.plist"
sleep 1
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.splitter.plist"
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.local-client.plist"
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.pairing.plist"
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.wake-recovery.plist"
if [[ -x "$support_dir/bin/StereoPairAgent" ]]; then
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.control-agent.plist"
fi

print "Installed local Snapcast stereo-pair services."
print "Check status with: $repo_root/integration/scripts/check-health.sh"
