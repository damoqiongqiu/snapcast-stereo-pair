#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
support_dir="$HOME/Library/Application Support/Snapcast"
log_dir="$HOME/Library/Logs/Snapcast"
launch_dir="$HOME/Library/LaunchAgents"
run_dir="$support_dir/run"
uid="$(id -u)"

source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config
require_pair_config
compute_pair_roles

"$repo_root/integration/scripts/build-macos.sh"
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
install -m 755 "$repo_root/.build/bin/capture-blackhole" "$homebrew_bin/snapcast-capture-blackhole"
install -m 644 "$repo_root/integration/capture/capture-blackhole-pa.c" "$support_dir/capture-blackhole-pa.c"
render_pair_template \
  "$repo_root/integration/config/snapserver.conf.in" \
  "$support_dir/snapserver.conf"

for name in server local-client route splitter pairing; do
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

for label in com.snapcast.local-client com.snapcast.capture com.snapcast.server com.snapcast.route com.snapcast.splitter com.snapcast.pairing; do
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
done
sleep 1

launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.route.plist"
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.server.plist"
sleep 1
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.splitter.plist"
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.local-client.plist"
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.pairing.plist"

print "Installed local Snapcast stereo-pair services."
print "Check status with: $repo_root/integration/scripts/check-health.sh"
