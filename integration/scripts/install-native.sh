#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
support_dir="$HOME/Library/Application Support/Snapcast"
launch_dir="$HOME/Library/LaunchAgents"
uid="$(id -u)"

"$repo_root/native/Packaging/build-native.sh"
mkdir -p "$support_dir/bin" "$launch_dir"
install -m 755 "$repo_root/native/.build/release/StereoPairAgent" "$support_dir/bin/StereoPairAgent"
install -m 755 "$repo_root/native/.build/release/mac-stereo-pairctl" "$support_dir/bin/mac-stereo-pairctl"

source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config
render_pair_template \
  "$repo_root/integration/launchagents/control-agent.plist.in" \
  "$launch_dir/com.snapcast.control-agent.plist"

launchctl bootout "gui/$uid/com.snapcast.control-agent" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.control-agent.plist"
print "Installed native control Agent and CLI."
