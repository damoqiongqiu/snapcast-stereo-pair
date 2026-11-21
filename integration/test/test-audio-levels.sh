#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cat > "$tmp_dir/set-audio-volume" <<'EOF'
#!/bin/zsh
set -euo pipefail
print -r -- "$*" >> "$AUDIO_VOLUME_TEST_LOG"
EOF
chmod +x "$tmp_dir/set-audio-volume"

export AUDIO_VOLUME_BIN="$tmp_dir/set-audio-volume"
export AUDIO_VOLUME_TEST_LOG="$tmp_dir/calls.log"
export CAPTURE_DEVICE_UID="BlackHole2ch_UID"
export LOCAL_OUTPUT_DEVICE="BuiltInSpeakerDevice"
export REMOTE_OUTPUT_DEVICE_UID="RemoteSpeakerDevice"

source "$repo_root/integration/scripts/audio-levels.sh"
ensure_audio_levels
ensure_remote_audio_level

expected=$'set BlackHole2ch_UID 100\nset BuiltInSpeakerDevice 100\nset RemoteSpeakerDevice 100'
[[ "$(cat "$AUDIO_VOLUME_TEST_LOG")" == "$expected" ]]

volume_bin="$repo_root/.build/bin/set-audio-volume"
[[ -x "$volume_bin" ]]
"$volume_bin" --help >/dev/null

print "Audio level tests passed"
