#!/bin/zsh

audio_profile_path() {
  local state_dir="$1"
  print -r -- "$state_dir/native-audio.json"
}

audio_profile_valid_volume() {
  local value="$1"
  [[ "$value" == <-> || "$value" == <->.<-> ]] || return 1
  awk -v value="$value" 'BEGIN { exit !(value >= 0 && value <= 100) }'
}

audio_save_native_profile() {
  local state_dir="$1"
  local capture_uid="$2"
  local switch_bin="$3"
  local volume_bin="$4"
  local current_json current_uid current_name current_volume

  current_json="$("$switch_bin" -f json -c -t output 2>/dev/null)" || return 1
  current_uid="$(print -r -- "$current_json" | jq -er '.uid')" || return 1
  current_name="$(print -r -- "$current_json" | jq -er '.name')" || return 1
  if [[ "$current_uid" == "$capture_uid" ]]; then
    return 0
  fi

  current_volume="$("$volume_bin" get "$current_uid" 2>/dev/null)" || return 1
  current_volume="${current_volume%%$'\n'*}"
  audio_profile_valid_volume "$current_volume" || return 1

  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  local profile temporary
  profile="$(audio_profile_path "$state_dir")"
  temporary="$(mktemp "$state_dir/.native-audio.XXXXXX")"
  jq -n \
    --arg outputUID "$current_uid" \
    --arg outputName "$current_name" \
    --argjson volumePercent "$current_volume" \
    --arg savedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{
      schemaVersion: 1,
      outputUID: $outputUID,
      outputName: $outputName,
      volumePercent: $volumePercent,
      savedAt: $savedAt
    }' > "$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$profile"
}

audio_restore_native_profile() {
  local state_dir="$1"
  local fallback_uid="$2"
  local switch_bin="$3"
  local volume_bin="$4"
  local profile output_uid output_volume
  local fallback_volume="${NATIVE_AUDIO_FALLBACK_VOLUME:-30}"
  audio_profile_valid_volume "$fallback_volume" || fallback_volume=30
  profile="$(audio_profile_path "$state_dir")"

  if [[ -f "$profile" ]]; then
    output_uid="$(jq -er '.outputUID' "$profile" 2>/dev/null || true)"
    output_volume="$(jq -er '.volumePercent' "$profile" 2>/dev/null || true)"
    if [[ -n "$output_uid" ]] &&
       audio_profile_valid_volume "$output_volume" &&
       "$volume_bin" set "$output_uid" "$output_volume" >/dev/null 2>&1 &&
       "$switch_bin" -u "$output_uid" -t output >/dev/null 2>&1; then
      return 0
    fi
  fi

  "$volume_bin" set "$fallback_uid" "$fallback_volume" >/dev/null 2>&1 &&
    "$switch_bin" -u "$fallback_uid" -t output
}
