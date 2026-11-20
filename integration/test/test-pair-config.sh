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
LOCAL_OUTPUT_DEVICE="BuiltInSpeakerDevice"
LOCAL_CLIENT_ID="local-role"
REMOTE_CLIENT_ID="remote-role"
EOF

source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config

route_sample=$'route to: default\n  interface: en7\n'
[[ "$(pair_interface_from_route "$route_sample")" == "en7" ]]

[[ "$REMOTE_USER" == "tester" ]]
[[ "$REMOTE_HOST" == "remote.local" ]]
[[ "$LEFT_CLIENT_ID" == "remote-role" ]]
[[ "$RIGHT_CLIENT_ID" == "local-role" ]]

REMOTE_HOST="override.local"
load_pair_config
[[ "$REMOTE_HOST" == "override.local" ]]

LEFT_IS_REMOTE=false
compute_pair_roles
[[ "$LEFT_CLIENT_ID" == "local-role" ]]
[[ "$RIGHT_CLIENT_ID" == "remote-role" ]]

source "$repo_root/integration/scripts/pair-config.sh"
render_pair_template \
  "$repo_root/integration/launchagents/local-client.plist.in" \
  "$tmp_dir/local.plist"
plutil -lint "$tmp_dir/local.plist"
plutil -p "$tmp_dir/local.plist" | grep -q "local-role"

print "Pair configuration tests passed"
