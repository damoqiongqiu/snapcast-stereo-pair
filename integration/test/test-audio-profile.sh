#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/SwitchAudioSource" <<'EOF'
#!/bin/zsh
set -euo pipefail
if [[ "$1" == "-f" && "$2" == "json" && "$3" == "-c" ]]; then
  print -r -- "${FAKE_CURRENT_OUTPUT:-}"
  exit 0
fi
if [[ "$1" == "-u" ]]; then
  print -r -- "$2" >> "$SWITCH_TEST_LOG"
  if [[ "$2" == "UnavailableDevice" ]]; then
    exit 1
  fi
  exit 0
fi
exit 2
EOF
cat > "$tmp_dir/set-audio-volume" <<'EOF'
#!/bin/zsh
set -euo pipefail
if [[ "$1" == "get" ]]; then
  print -r -- "${FAKE_CURRENT_VOLUME:-37.00}"
  exit 0
fi
if [[ "$1" == "set" ]]; then
  print -r -- "set $2 $3" >> "$VOLUME_TEST_LOG"
  exit 0
fi
exit 2
EOF
chmod 755 "$tmp_dir/SwitchAudioSource" "$tmp_dir/set-audio-volume"
export SWITCH_TEST_LOG="$tmp_dir/switch.log"
export VOLUME_TEST_LOG="$tmp_dir/volume.log"
export FAKE_CURRENT_OUTPUT='{"name":"USB DAC","uid":"USBDAC","id":"42","type":"output"}'
export FAKE_CURRENT_VOLUME='37.00'

source "$repo_root/integration/scripts/audio-profile.sh"
audio_save_native_profile \
  "$tmp_dir/state" \
  "BlackHole2ch_UID" \
  "$tmp_dir/SwitchAudioSource" \
  "$tmp_dir/set-audio-volume"

profile="$tmp_dir/state/native-audio.json"
[[ -f "$profile" ]]
[[ "$(stat -f '%Lp' "$profile")" == "600" ]]
jq -e '.outputUID == "USBDAC" and .outputName == "USB DAC" and .volumePercent == 37' "$profile" >/dev/null

audio_restore_native_profile \
  "$tmp_dir/state" \
  "BuiltInSpeakerDevice" \
  "$tmp_dir/SwitchAudioSource" \
  "$tmp_dir/set-audio-volume"

[[ "$(cat "$VOLUME_TEST_LOG")" == "set USBDAC 37.00" ]]
[[ "$(cat "$SWITCH_TEST_LOG")" == "USBDAC" ]]

: > "$SWITCH_TEST_LOG"
: > "$VOLUME_TEST_LOG"
export FAKE_CURRENT_OUTPUT='{"name":"BlackHole 2ch","uid":"BlackHole2ch_UID","id":"89","type":"output"}'
audio_save_native_profile \
  "$tmp_dir/state" \
  "BlackHole2ch_UID" \
  "$tmp_dir/SwitchAudioSource" \
  "$tmp_dir/set-audio-volume"
jq -e '.outputUID == "USBDAC" and .volumePercent == 37' "$profile" >/dev/null

jq -n '{schemaVersion:1,outputUID:"UnavailableDevice",outputName:"Gone",volumePercent:82}' > "$profile"
audio_restore_native_profile \
  "$tmp_dir/state" \
  "BuiltInSpeakerDevice" \
  "$tmp_dir/SwitchAudioSource" \
  "$tmp_dir/set-audio-volume"

[[ "$(tail -1 "$VOLUME_TEST_LOG")" == "set BuiltInSpeakerDevice 30" ]]
[[ "$(tail -1 "$SWITCH_TEST_LOG")" == "BuiltInSpeakerDevice" ]]

print "Audio profile tests passed"
