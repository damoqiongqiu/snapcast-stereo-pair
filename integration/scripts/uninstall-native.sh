#!/bin/zsh
set -euo pipefail

support_dir="$HOME/Library/Application Support/Snapcast"
launch_dir="$HOME/Library/LaunchAgents"
app_path="$HOME/Applications/MacBook Stereo Pair.app"
uid="$(id -u)"

launchctl bootout "gui/$uid/com.snapcast.control-agent" 2>/dev/null || true

rm -f "$launch_dir/com.snapcast.control-agent.plist"
rm -f "$support_dir/bin/StereoPairAgent"
rm -f "$support_dir/bin/mac-stereo-pairctl"
rm -f "$support_dir/setup/native-setup-helper.sh"
rm -f "$support_dir/setup/source-root"
rmdir "$support_dir/setup" 2>/dev/null || true
rm -rf "$app_path"

print "Removed the native console, control Agent, and CLI."
print "Audio runtime services and user configuration were preserved."
