#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
server_pid=""
left_pid=""
right_pid=""
left_test_client_id="route-left-7"
right_test_client_id="route-right-3"

cleanup() {
  for pid in "$left_pid" "$right_pid" "$server_pid"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cat > "$tmp_dir/snapserver.conf" <<EOF
[server]
threads = 2
mdns_enabled = false
datadir = $tmp_dir/data

[http]
enabled = true
bind_to_address = 127.0.0.1
port = 19180

[tcp-control]
enabled = true
bind_to_address = 127.0.0.1
port = 19105

[tcp-streaming]
enabled = true
bind_to_address = 127.0.0.1
port = 19104

[stream]
source = process:///usr/bin/yes?name=LeftAudio&sampleformat=48000:24:1
source = process:///usr/bin/yes?name=RightAudio&sampleformat=48000:24:1
sampleformat = 48000:24:1
codec = pcm
chunk_ms = 20
buffer = 200
EOF

mkdir -p "$tmp_dir/data"
"$repo_root/.build/bin/snapserver" -c "$tmp_dir/snapserver.conf" >"$tmp_dir/server.log" 2>&1 &
server_pid=$!
sleep 1

"$repo_root/.build/bin/snapclient" tcp://127.0.0.1:19104 \
  --hostID "$left_test_client_id" --player file:filename=/dev/null \
  --logsink file:"$tmp_dir/$left_test_client_id.log" >/dev/null 2>&1 &
left_pid=$!
"$repo_root/.build/bin/snapclient" tcp://127.0.0.1:19104 \
  --hostID "$right_test_client_id" --player file:filename=/dev/null \
  --logsink file:"$tmp_dir/$right_test_client_id.log" >/dev/null 2>&1 &
right_pid=$!

for _ in {1..50}; do
  if curl -fsS http://127.0.0.1:19180/jsonrpc \
    -H 'Content-Type: application/json' \
    --data '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' 2>/dev/null |
    jq -e --arg left "$left_test_client_id" --arg right "$right_test_client_id" '
      ([.result.server.groups[].clients[].id] | sort) == ([$left, $right] | sort)
    ' >/dev/null; then
    break
  fi
  sleep 0.1
done

SNAPSERVER_HTTP=http://127.0.0.1:19180 \
LEFT_CLIENT_ID="$left_test_client_id" \
RIGHT_CLIENT_ID="$right_test_client_id" \
SNAPCAST_STATE_DIR="$tmp_dir/state" \
  "$repo_root/integration/scripts/ensure-pair-routing.sh"

status_json="$(curl -fsS http://127.0.0.1:19180/jsonrpc \
  -H 'Content-Type: application/json' \
  --data '{"id":2,"jsonrpc":"2.0","method":"Server.GetStatus"}')"

print -r -- "$status_json" | jq -e \
  --arg left "$left_test_client_id" \
  --arg right "$right_test_client_id" '
  [
    .result.server.groups[]
    | {
        stream_id,
        clients: [.clients[].id]
      }
  ]
  | any(.stream_id == "LeftAudio" and .clients == [$left])
    and any(.stream_id == "RightAudio" and .clients == [$right])
' >/dev/null

groups_before="$(print -r -- "$status_json" | jq -r '[.result.server.groups[].id] | sort | join(",")')"
SNAPSERVER_HTTP=http://127.0.0.1:19180 \
LEFT_CLIENT_ID="$left_test_client_id" \
RIGHT_CLIENT_ID="$right_test_client_id" \
SNAPCAST_STATE_DIR="$tmp_dir/state" \
  "$repo_root/integration/scripts/ensure-pair-routing.sh"
status_after_json="$(curl -fsS http://127.0.0.1:19180/jsonrpc \
  -H 'Content-Type: application/json' \
  --data '{"id":3,"jsonrpc":"2.0","method":"Server.GetStatus"}')"
groups_after="$(print -r -- "$status_after_json" | jq -r '[.result.server.groups[].id] | sort | join(",")')"

[[ "$groups_before" == "$groups_after" ]]
print "Pair routing tests passed"
