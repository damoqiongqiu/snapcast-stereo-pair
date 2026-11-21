#!/bin/zsh

CAPTURE_DEVICE_UID="${CAPTURE_DEVICE_UID:-@CAPTURE_DEVICE_UID@}"
LOCAL_OUTPUT_DEVICE="${LOCAL_OUTPUT_DEVICE:-@LOCAL_OUTPUT_DEVICE@}"
REMOTE_OUTPUT_DEVICE_UID="${REMOTE_OUTPUT_DEVICE_UID:-@REMOTE_OUTPUT_DEVICE_UID@}"

audio_volume_bin() {
  print -r -- "${AUDIO_VOLUME_BIN:-${SUPPORT_DIR:-$HOME/Library/Application Support/Snapcast}/bin/set-audio-volume}"
}

ensure_audio_levels() {
  local volume_bin
  volume_bin="$(audio_volume_bin)"
  if [[ ! -x "$volume_bin" ]]; then
    print -u2 "CoreAudio volume helper is missing: $volume_bin"
    return 1
  fi
  "$volume_bin" set "$CAPTURE_DEVICE_UID" 100
  "$volume_bin" set "$LOCAL_OUTPUT_DEVICE" 100
}

ensure_remote_audio_level() {
  local volume_bin
  volume_bin="$(audio_volume_bin)"
  if [[ ! -x "$volume_bin" ]]; then
    print -u2 "CoreAudio volume helper is missing: $volume_bin"
    return 1
  fi
  "$volume_bin" set "$REMOTE_OUTPUT_DEVICE_UID" 100
}
