#!/bin/zsh
set -euo pipefail

support_dir="${SUPPORT_DIR:-@SUPPORT_DIR@}"
switch_bin="${SWITCH_AUDIO_SOURCE_BIN:-SwitchAudioSource}"
launchctl_bin="${LAUNCHCTL_BIN:-launchctl}"
uid="${WAKE_RECOVERY_UID:-$(id -u)}"
state_dir="${SNAPCAST_STATE_DIR:-$support_dir/state}"

if [[ -f "$support_dir/health-marker.sh" ]]; then
  source "$support_dir/health-marker.sh"
  finish_health_marker() {
    local exit_code=$?
    trap - EXIT
    if (( exit_code == 0 )); then
      write_health_marker "$state_dir/wake-local.json" true 0 "local wake recovery completed"
    else
      write_health_marker "$state_dir/wake-local.json" false "$exit_code" "local wake recovery failed"
    fi
    exit "$exit_code"
  }
  trap finish_health_marker EXIT
fi

/bin/sleep "${WAKE_RECOVERY_DELAY:-2}"
source "$support_dir/audio-levels.sh"

"$switch_bin" -s "${CAPTURE_DEVICE:-@CAPTURE_DEVICE@}" -t output
ensure_audio_levels
"$launchctl_bin" kickstart -k "gui/$uid/com.snapcast.splitter"
"$launchctl_bin" kickstart -k "gui/$uid/com.snapcast.local-client"
