#!/bin/zsh
set -euo pipefail

support_dir="${SUPPORT_DIR:-@SUPPORT_DIR@}"
launchctl_bin="${LAUNCHCTL_BIN:-launchctl}"
volume_bin="${AUDIO_VOLUME_BIN:-$support_dir/bin/set-audio-volume}"
uid="${WAKE_RECOVERY_UID:-$(id -u)}"
state_dir="${SNAPCAST_STATE_DIR:-$support_dir/state}"

if [[ -f "$support_dir/health-marker.sh" ]]; then
  source "$support_dir/health-marker.sh"
  finish_health_marker() {
    local exit_code=$?
    trap - EXIT
    if (( exit_code == 0 )); then
      write_health_marker "$state_dir/wake-remote.json" true 0 "remote wake recovery completed"
    else
      write_health_marker "$state_dir/wake-remote.json" false "$exit_code" "remote wake recovery failed"
    fi
    exit "$exit_code"
  }
  trap finish_health_marker EXIT
fi

/bin/sleep "${WAKE_RECOVERY_DELAY:-2}"
"$volume_bin" set "${REMOTE_OUTPUT_DEVICE_UID:-@REMOTE_OUTPUT_DEVICE_UID@}" 100
"$launchctl_bin" kickstart -k "gui/$uid/com.snapcast.remote-client"
