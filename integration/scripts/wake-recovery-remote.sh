#!/bin/zsh
set -euo pipefail

support_dir="${SUPPORT_DIR:-@SUPPORT_DIR@}"
launchctl_bin="${LAUNCHCTL_BIN:-launchctl}"
volume_bin="${AUDIO_VOLUME_BIN:-$support_dir/bin/set-audio-volume}"
uid="${WAKE_RECOVERY_UID:-$(id -u)}"

/bin/sleep "${WAKE_RECOVERY_DELAY:-2}"
"$volume_bin" set "${REMOTE_OUTPUT_DEVICE_UID:-@REMOTE_OUTPUT_DEVICE_UID@}" 100
"$launchctl_bin" kickstart -k "gui/$uid/com.snapcast.remote-client"
