#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
export PAIR_CONFIG_FILE="$tmp_dir/pair.env"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cat > "$PAIR_CONFIG_FILE" <<EOF
REMOTE_USER="tester"
REMOTE_HOST="remote.local"
SOURCE_HOST="10.0.0.10"
LEFT_IS_REMOTE=true
CAPTURE_DEVICE="BlackHole 2ch"
CAPTURE_DEVICE_UID="BlackHole2ch_UID"
LOCAL_OUTPUT_DEVICE="BuiltInSpeakerDevice"
REMOTE_OUTPUT_DEVICE_UID="BuiltInSpeakerDevice"
LOCAL_CLIENT_ID="local-role"
REMOTE_CLIENT_ID="remote-role"
EOF

source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config

route_sample=$'route to: default\n  interface: en7\n'
[[ "$(pair_interface_from_route "$route_sample")" == "en7" ]]

[[ "$REMOTE_USER" == "tester" ]]
[[ "$REMOTE_HOST" == "remote.local" ]]
[[ "$CAPTURE_DEVICE_UID" == "BlackHole2ch_UID" ]]
[[ "$REMOTE_OUTPUT_DEVICE_UID" == "BuiltInSpeakerDevice" ]]
[[ "$LEFT_CLIENT_ID" == "remote-role" ]]
[[ "$RIGHT_CLIENT_ID" == "local-role" ]]

REMOTE_HOST="override.local"
load_pair_config
[[ "$REMOTE_HOST" == "override.local" ]]

LEFT_IS_REMOTE=false
compute_pair_roles
[[ "$LEFT_CLIENT_ID" == "local-role" ]]
[[ "$RIGHT_CLIENT_ID" == "remote-role" ]]

unset REMOTE_USER REMOTE_HOST SOURCE_HOST LEFT_IS_REMOTE
prepare_local_only_config
[[ "$REMOTE_USER" == "pending-remote" ]]
[[ "$REMOTE_HOST" == "pending.invalid" ]]
[[ "$LEFT_IS_REMOTE" == "true" ]]
require_pair_config

source "$repo_root/integration/scripts/pair-config.sh"
render_pair_template \
  "$repo_root/integration/launchagents/local-client.plist.in" \
  "$tmp_dir/local.plist"
plutil -lint "$tmp_dir/local.plist"
plutil -p "$tmp_dir/local.plist" | grep -q "local-role"

render_pair_template \
  "$repo_root/integration/scripts/audio-levels.sh" \
  "$tmp_dir/audio-levels.sh"
grep -q "BlackHole2ch_UID" "$tmp_dir/audio-levels.sh"
grep -q "BuiltInSpeakerDevice" "$tmp_dir/audio-levels.sh"
! grep -q "@CAPTURE_DEVICE_UID@" "$tmp_dir/audio-levels.sh"
! grep -q "@REMOTE_OUTPUT_DEVICE_UID@" "$tmp_dir/audio-levels.sh"

CONFIG_SCHEMA=2
save_pair_config
load_pair_config
! validate_pair_config_schema

unset CONFIG_SCHEMA REMOTE_USER REMOTE_HOST SOURCE_HOST LEFT_IS_REMOTE
unset CAPTURE_DEVICE CAPTURE_DEVICE_UID LOCAL_OUTPUT_DEVICE
unset NATIVE_OUTPUT_DEVICE_UID REMOTE_OUTPUT_DEVICE_UID
unset LOCAL_CLIENT_ID REMOTE_CLIENT_ID
sed -i '' '/^CONFIG_SCHEMA=/d' "$PAIR_CONFIG_FILE"
load_pair_config
migrate_pair_config_schema
grep -q '^CONFIG_SCHEMA="1"$' "$PAIR_CONFIG_FILE"
grep -q '^REMOTE_USER="pending-remote"$' "$PAIR_CONFIG_FILE"

print "Pair configuration tests passed"
