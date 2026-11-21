#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
state_dir="$tmp_dir/state"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

source "$repo_root/integration/scripts/health-marker.sh"

write_health_marker "$state_dir/pairing.json" true 0 "waiting for both clients"
jq -e '.success == true and .exitCode == 0 and .message == "waiting for both clients"' \
  "$state_dir/pairing.json" >/dev/null

print -r -- 'not-json' > "$state_dir/pairing.json"
write_health_marker "$state_dir/pairing.json" false 5 "routing failed"
jq -e '.success == false and .exitCode == 5 and .message == "routing failed"' \
  "$state_dir/pairing.json" >/dev/null

[[ "$(find "$state_dir" -name '.health-marker.*' | wc -l | tr -d ' ')" == "0" ]]

print "Health marker tests passed"
