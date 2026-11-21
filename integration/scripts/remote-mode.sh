#!/bin/zsh
set -euo pipefail

support_dir="@SUPPORT_DIR@"
launch_dir="$HOME/Library/LaunchAgents"
uid="$(id -u)"
mode="${1:-}"

stop_runtime() {
  for label in com.snapcast.remote-client com.snapcast.remote-wake-recovery; do
    launchctl bootout "gui/$uid/$label" 2>/dev/null || true
    launchctl disable "gui/$uid/$label" 2>/dev/null || true
  done
  "$support_dir/bin/set-audio-volume" set "@REMOTE_OUTPUT_DEVICE_UID@" 100
  "@HOMEBREW_BIN@/SwitchAudioSource" -u "@REMOTE_OUTPUT_DEVICE_UID@" -t output
}

start_runtime() {
  stop_runtime
  for label in com.snapcast.remote-client com.snapcast.remote-wake-recovery; do
    launchctl enable "gui/$uid/$label"
  done
  "$support_dir/bin/set-audio-volume" set "@REMOTE_OUTPUT_DEVICE_UID@" 100
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.remote-client.plist"
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.remote-wake-recovery.plist"
}

case "$mode" in
  system)
    stop_runtime
    print "Remote native audio mode enabled."
    ;;
  snapcast)
    start_runtime
    print "Remote stereo-pair mode enabled."
    ;;
  *)
    print -u2 "Usage: $0 {snapcast|system}"
    exit 2
    ;;
esac
