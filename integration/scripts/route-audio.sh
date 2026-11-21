#!/bin/zsh
set -euo pipefail

source "@SUPPORT_DIR@/audio-levels.sh"
SwitchAudioSource -s "@CAPTURE_DEVICE@" -t output
ensure_audio_levels
