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

bootstrap_with_retry() {
  local plist="$1"
  local attempt
  for attempt in 1 2 3; do
    if launchctl bootstrap "gui/$uid" "$plist" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  launchctl bootstrap "gui/$uid" "$plist"
}

start_runtime() {
  local capture_uid=""
  local service_running=false
  if launchctl print "gui/$uid/com.snapcast.remote-client" >/dev/null 2>&1; then
    service_running=true
    capture_uid="@REMOTE_OUTPUT_DEVICE_UID@"
  fi
  if audio_should_capture_native_profile "$support_dir/state" "$service_running"; then
    audio_save_native_profile \
      "$support_dir/state" \
      "$capture_uid" \
      "@HOMEBREW_BIN@/SwitchAudioSource" \
      "$support_dir/bin/set-audio-volume" || {
        print -u2 "Could not save the remote Mac audio output and volume; mode was not changed."
        return 1
      }
  fi
  stop_services
  for label in com.snapcast.remote-client com.snapcast.remote-wake-recovery; do
    launchctl enable "gui/$uid/$label"
  done
  sleep 1
  "$support_dir/bin/set-audio-volume" set "@REMOTE_OUTPUT_DEVICE_UID@" 100
  bootstrap_with_retry "$launch_dir/com.snapcast.remote-client.plist"
  bootstrap_with_retry "$launch_dir/com.snapcast.remote-wake-recovery.plist"
  audio_write_persisted_mode "$support_dir/state" snapcast
}

case "$mode" in
  system)
    stop_services
    audio_restore_native_profile \
      "$support_dir/state" \
      "@REMOTE_OUTPUT_DEVICE_UID@" \
      "@HOMEBREW_BIN@/SwitchAudioSource" \
      "$support_dir/bin/set-audio-volume"
    audio_write_persisted_mode "$support_dir/state" system
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
