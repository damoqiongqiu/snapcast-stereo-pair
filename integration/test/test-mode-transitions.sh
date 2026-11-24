#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

swift test --package-path "$repo_root/native" --filter ModeCoordinatorTests
zsh -n "$repo_root/integration/scripts/set-mode.sh"
zsh -n "$repo_root/integration/scripts/remote-mode.sh"

source "$repo_root/integration/scripts/pair-config.sh"
REMOTE_USER=tester
REMOTE_HOST=192.0.2.10
LEFT_IS_REMOTE=true
load_pair_config
compute_pair_roles
PAIR_RENDER_HOMEBREW_BIN="$tmp_dir/homebrew/bin" \
render_pair_template \
  "$repo_root/integration/scripts/remote-mode.sh" \
  "$tmp_dir/remote-mode.sh"
zsh -n "$tmp_dir/remote-mode.sh"
[[ "$(grep -c '@[A-Z_]*@' "$tmp_dir/remote-mode.sh")" -eq 0 ]]
grep -Fq "$tmp_dir/homebrew/bin/SwitchAudioSource" "$tmp_dir/remote-mode.sh"

local_home="$tmp_dir/home"
support_dir="$local_home/Library/Application Support/Snapcast"
fake_bin="$tmp_dir/fake-bin"
mkdir -p "$support_dir/bin" "$support_dir/state" "$fake_bin"

cat > "$fake_bin/SwitchAudioSource" <<'EOF'
#!/bin/zsh
if [[ "$*" == *"-f json -c -t output"* ]]; then
  print -r -- '{"name":"Native Speaker","uid":"NativeSpeaker","id":"1","type":"output"}'
fi
print -r -- "switch $*" >> "$MODE_TRANSITION_TEST_LOG"
EOF
cat > "$support_dir/bin/set-audio-volume" <<'EOF'
#!/bin/zsh
if [[ "${1:-}" == "get" ]]; then
  print -r -- "37.00"
fi
print -r -- "volume $*" >> "$MODE_TRANSITION_TEST_LOG"
EOF
cat > "$fake_bin/launchctl" <<'EOF'
#!/bin/zsh
print -r -- "launchctl $*" >> "$MODE_TRANSITION_TEST_LOG"
EOF
cat > "$fake_bin/sleep" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$fake_bin/SwitchAudioSource" "$support_dir/bin/set-audio-volume" \
  "$fake_bin/launchctl" "$fake_bin/sleep"

cat > "$support_dir/state/native-audio.json" <<'EOF'
{"schemaVersion":1,"outputUID":"NativeSpeaker","outputName":"Native Speaker","volumePercent":37}
EOF

PAIR_RENDER_HOME="$local_home" \
PAIR_RENDER_HOMEBREW_BIN="$fake_bin" \
CAPTURE_DEVICE="BlackHole 2ch" \
CAPTURE_DEVICE_UID="BlackHole2ch_UID" \
NATIVE_OUTPUT_DEVICE_UID="NativeSpeaker" \
render_pair_template \
  "$repo_root/integration/scripts/set-mode.sh" \
  "$support_dir/set-mode.sh"
chmod +x "$support_dir/set-mode.sh"

PAIR_RENDER_HOME="$local_home" \
PAIR_RENDER_HOMEBREW_BIN="$fake_bin" \
CAPTURE_DEVICE_UID="BlackHole2ch_UID" \
LOCAL_OUTPUT_DEVICE="NativeSpeaker" \
REMOTE_OUTPUT_DEVICE_UID="RemoteSpeaker" \
render_pair_template \
  "$repo_root/integration/scripts/audio-levels.sh" \
  "$support_dir/audio-levels.sh"
install -m 644 "$repo_root/integration/scripts/audio-profile.sh" "$support_dir/audio-profile.sh"

export MODE_TRANSITION_TEST_LOG="$tmp_dir/mode-calls.log"
PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$support_dir/set-mode.sh" snapcast >/dev/null
jq -e '.mode == "snapcast"' "$support_dir/state/audio-mode.json" >/dev/null

PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$support_dir/set-mode.sh" native >/dev/null
jq -e '.mode == "system"' "$support_dir/state/audio-mode.json" >/dev/null

print "Mode transition tests passed"
