#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
support_dir="$HOME/Library/Application Support/Snapcast"
launch_dir="$HOME/Library/LaunchAgents"
uid="$(id -u)"

"$repo_root/native/Packaging/build-native.sh"
app_path="$repo_root/.build/MacBook Stereo Pair.app"
"$repo_root/native/Packaging/build-app.sh"
mkdir -p "$support_dir/bin" "$launch_dir" "$HOME/Applications"
mkdir -p "$support_dir/setup"
install -m 755 "$repo_root/native/.build/release/StereoPairAgent" "$support_dir/bin/StereoPairAgent"
install -m 755 "$repo_root/native/.build/release/mac-stereo-pairctl" "$support_dir/bin/mac-stereo-pairctl"
install -m 755 "$repo_root/integration/scripts/native-setup-helper.sh" \
  "$support_dir/setup/native-setup-helper.sh"
print -r -- "$repo_root" > "$support_dir/setup/source-root"
chmod 600 "$support_dir/setup/source-root"
rm -rf "$HOME/Applications/MacBook Stereo Pair.app"
cp -R "$app_path" "$HOME/Applications/MacBook Stereo Pair.app"

source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config
render_pair_template \
  "$repo_root/integration/launchagents/control-agent.plist.in" \
  "$launch_dir/com.snapcast.control-agent.plist"

launchctl bootout "gui/$uid/com.snapcast.control-agent" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.control-agent.plist"
print "Installed MacBook Stereo Pair.app, control Agent, and CLI."
