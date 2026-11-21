#!/bin/zsh
set -euo pipefail

support_dir="${SUPPORT_DIR:-@SUPPORT_DIR@}"
switch_bin="${SWITCH_AUDIO_SOURCE_BIN:-SwitchAudioSource}"
launchctl_bin="${LAUNCHCTL_BIN:-launchctl}"
uid="${WAKE_RECOVERY_UID:-$(id -u)}"

/bin/sleep "${WAKE_RECOVERY_DELAY:-2}"
source "$support_dir/audio-levels.sh"

"$switch_bin" -s "${CAPTURE_DEVICE:-@CAPTURE_DEVICE@}" -t output
ensure_audio_levels
"$launchctl_bin" kickstart -k "gui/$uid/com.snapcast.splitter"
"$launchctl_bin" kickstart -k "gui/$uid/com.snapcast.local-client"
