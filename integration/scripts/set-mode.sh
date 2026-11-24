#!/bin/zsh
set -euo pipefail

uid="$(id -u)"
launch_dir="$HOME/Library/LaunchAgents"
source "@SUPPORT_DIR@/audio-levels.sh"
source "@SUPPORT_DIR@/audio-profile.sh"

stop_snapcast() {
  for label in com.snapcast.local-client com.snapcast.capture com.snapcast.server com.snapcast.route com.snapcast.splitter com.snapcast.pairing com.snapcast.wake-recovery; do
    launchctl bootout "gui/$uid/$label" 2>/dev/null || true
  done
}

start_snapcast() {
  audio_save_native_profile \
    "@SUPPORT_DIR@/state" \
    "@CAPTURE_DEVICE_UID@" \
    SwitchAudioSource \
    "@SUPPORT_DIR@/bin/set-audio-volume" || {
      print -u2 "Could not save the current Mac audio output and volume; mode was not changed."
      return 1
    }
  stop_snapcast
  sleep 1
  for label in com.snapcast.local-client com.snapcast.server com.snapcast.route com.snapcast.splitter com.snapcast.pairing com.snapcast.wake-recovery; do
    launchctl enable "gui/$uid/$label"
  done
  SwitchAudioSource -s "@CAPTURE_DEVICE@" -t output
  ensure_audio_levels
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.route.plist"
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.server.plist"
  sleep 1
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.splitter.plist"
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.local-client.plist"
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.pairing.plist"
  launchctl bootstrap "gui/$uid" "$launch_dir/com.snapcast.wake-recovery.plist"
  sleep 1
  launchctl kickstart -k "gui/$uid/com.snapcast.splitter"
  audio_write_persisted_mode "@SUPPORT_DIR@/state" snapcast
  print "Snapcast stereo-pair mode enabled."
}

case "${1:-}" in
  snapcast)
    start_snapcast
    ;;
  native)
    stop_snapcast
    for label in com.snapcast.local-client com.snapcast.server com.snapcast.route com.snapcast.splitter com.snapcast.pairing com.snapcast.wake-recovery; do
      launchctl disable "gui/$uid/$label"
    done
    audio_restore_native_profile \
      "@SUPPORT_DIR@/state" \
      "@NATIVE_OUTPUT_DEVICE_UID@" \
      SwitchAudioSource \
      "@SUPPORT_DIR@/bin/set-audio-volume"
    audio_write_persisted_mode "@SUPPORT_DIR@/state" system
    print "Native macOS audio mode enabled across future logins."
    ;;
  *)
    print -u2 "Usage: $0 {snapcast|native}"
    exit 2
    ;;
esac
