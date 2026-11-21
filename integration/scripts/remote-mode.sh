#!/bin/zsh
set -euo pipefail

support_dir="@SUPPORT_DIR@"
launch_dir="$HOME/Library/LaunchAgents"
uid="$(id -u)"
mode="${1:-}"
source "$support_dir/audio-profile.sh"

stop_services() {
  for label in com.snapcast.remote-client com.snapcast.remote-wake-recovery; do
    launchctl bootout "gui/$uid/$label" 2>/dev/null || true
    launchctl disable "gui/$uid/$label" 2>/dev/null || true
  done
}

start_runtime() {
  local capture_uid=""
  if launchctl print "gui/$uid/com.snapcast.remote-client" >/dev/null 2>&1; then
    capture_uid="@REMOTE_OUTPUT_DEVICE_UID@"
  fi
  audio_save_native_profile \
    "$support_dir/state" \
    "$capture_uid" \
    "@HOMEBREW_BIN@/SwitchAudioSource" \
    "$support_dir/bin/set-audio-volume" || {
      print -u2 "Could not save the remote Mac audio output and volume; mode was not changed."
      return 1
    }
  stop_services
  for label in com.snapcast.remote-client com.snapcast.remote-wake-recovery; do
    launchctl enable "gui/$uid/$label"
  done
  sleep 1
  "$support_dir/bin/set-audio-volume" set "@REMOTE_OUTPUT_DEVICE_UID@" 100
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.remote-client.plist"
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.remote-wake-recovery.plist"
}

case "$mode" in
  system)
    stop_services
    audio_restore_native_profile \
      "$support_dir/state" \
      "@REMOTE_OUTPUT_DEVICE_UID@" \
      "@HOMEBREW_BIN@/SwitchAudioSource" \
      "$support_dir/bin/set-audio-volume"
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
