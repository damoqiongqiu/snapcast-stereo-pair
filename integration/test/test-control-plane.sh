#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
socket="$tmp_dir/control.sock"
agent_pid=""

cleanup() {
  if [[ -n "$agent_pid" ]]; then
    kill "$agent_pid" 2>/dev/null || true
    wait "$agent_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

swift build --package-path "$repo_root/native" >/dev/null
bin_dir="$(swift build --package-path "$repo_root/native" --show-bin-path)"

SNAPCAST_CONTROL_SOCKET="$socket" "$bin_dir/StereoPairAgent" >"$tmp_dir/agent.log" 2>&1 &
agent_pid=$!

for _ in {1..100}; do
  [[ -S "$socket" ]] && break
  sleep 0.05
done
[[ -S "$socket" ]]
[[ "$(stat -f '%Lp' "$socket")" == "600" ]]

status_json="$(SNAPCAST_CONTROL_SOCKET="$socket" "$bin_dir/mac-stereo-pairctl" status)"
print -r -- "$status_json" | jq -e 'has("snapshot")' >/dev/null
print -r -- "$status_json" | jq -e '.snapshot._0.protocolVersion == 1' >/dev/null

set +e
"$bin_dir/mac-stereo-pairctl" unknown-command >/dev/null 2>&1
unknown_status=$?
set -e
[[ "$unknown_status" -eq 2 ]]

print "Control plane tests passed"
