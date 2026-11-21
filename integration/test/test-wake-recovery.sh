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
print -r -- "volume $*" >> "$WAKE_RECOVERY_TEST_LOG"
EOF
cat > "$tmp_dir/SwitchAudioSource" <<'EOF'
#!/bin/zsh
print -r -- "switch $*" >> "$WAKE_RECOVERY_TEST_LOG"
EOF
cat > "$tmp_dir/launchctl" <<'EOF'
#!/bin/zsh
print -r -- "launchctl $*" >> "$WAKE_RECOVERY_TEST_LOG"
EOF
chmod +x "$tmp_dir/set-audio-volume" "$tmp_dir/SwitchAudioSource" "$tmp_dir/launchctl"

export WAKE_RECOVERY_TEST_LOG="$tmp_dir/calls.log"
export WAKE_RECOVERY_DELAY=0
export AUDIO_VOLUME_BIN="$tmp_dir/set-audio-volume"
export SWITCH_AUDIO_SOURCE_BIN="$tmp_dir/SwitchAudioSource"
export LAUNCHCTL_BIN="$tmp_dir/launchctl"
export SUPPORT_DIR="$repo_root/integration/scripts"
export CAPTURE_DEVICE_UID="BlackHole2ch_UID"
export LOCAL_OUTPUT_DEVICE="BuiltInSpeakerDevice"
export REMOTE_OUTPUT_DEVICE_UID="RemoteSpeakerDevice"
export CAPTURE_DEVICE="BlackHole 2ch"
export LOCAL_CLIENT_ID="local-role"
export REMOTE_CLIENT_ID="remote-role"

"$repo_root/integration/scripts/wake-recovery-local.sh"

uid="$(id -u)"
expected_local="switch -s BlackHole 2ch -t output
volume set BlackHole2ch_UID 100
volume set BuiltInSpeakerDevice 100
launchctl kickstart -k gui/$uid/com.snapcast.splitter
launchctl kickstart -k gui/$uid/com.snapcast.local-client"
[[ "$(cat "$WAKE_RECOVERY_TEST_LOG")" == "$expected_local" ]]

: > "$WAKE_RECOVERY_TEST_LOG"
WAKE_RECOVERY_UID=502 "$repo_root/integration/scripts/wake-recovery-remote.sh"

expected_remote=$'volume set RemoteSpeakerDevice 100\nlaunchctl kickstart -k gui/502/com.snapcast.remote-client'
[[ "$(cat "$WAKE_RECOVERY_TEST_LOG")" == "$expected_remote" ]]

listener="$repo_root/.build/bin/wake-recovery-listener"
[[ -x "$listener" ]]
set +e
usage="$("$listener" 2>&1)"
listener_status=$?
set -e
[[ "$listener_status" -eq 2 ]]
[[ "$usage" == Usage:* ]]

print "Wake recovery tests passed"
