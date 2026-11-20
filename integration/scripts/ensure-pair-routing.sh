#!/bin/zsh
set -euo pipefail

api="${SNAPSERVER_HTTP:-http://127.0.0.1:1780}"
request_id=0
LEFT_CLIENT_ID="${LEFT_CLIENT_ID:-@LEFT_CLIENT_ID@}"
RIGHT_CLIENT_ID="${RIGHT_CLIENT_ID:-@RIGHT_CLIENT_ID@}"

rpc() {
  local payload="$1"
  local response
  response="$(curl -fsS "$api/jsonrpc" \
    -H 'Content-Type: application/json' \
    --data "$payload")" || return 1
  print -r -- "$response" | jq -e 'has("result")' >/dev/null || {
    print -u2 "Snapserver JSON-RPC error: $response"
    return 1
  }
  print -r -- "$response"
}

next_id() {
  request_id=$((request_id + 1))
  print -r -- "$request_id"
}

group_for_client() {
  local status_json="$1"
  local client_id="$2"
  print -r -- "$status_json" | jq -r --arg client_id "$client_id" '
    .result.server.groups[]
    | select(any(.clients[]; .id == $client_id and .connected == true))
    | .id
  ' | head -n 1
}

stream_for_group() {
  local status_json="$1"
  local group_id="$2"
  print -r -- "$status_json" | jq -r --arg group_id "$group_id" '
    .result.server.groups[]
    | select(.id == $group_id)
    | .stream_id
  '
}

server_status="$(rpc "{\"id\":$(next_id),\"jsonrpc\":\"2.0\",\"method\":\"Server.GetStatus\"}")"

both_connected="$(print -r -- "$server_status" | jq -r \
  --arg left_id "$LEFT_CLIENT_ID" \
  --arg right_id "$RIGHT_CLIENT_ID" '
  ([.result.server.groups[].clients[] | select(.id == $left_id and .connected)] | length) == 1
  and ([.result.server.groups[].clients[] | select(.id == $right_id and .connected)] | length) == 1
')"
if [[ "$both_connected" != "true" ]]; then
  exit 0
fi

left_group="$(group_for_client "$server_status" "$LEFT_CLIENT_ID")"
right_group="$(group_for_client "$server_status" "$RIGHT_CLIENT_ID")"

if [[ -z "$left_group" || -z "$right_group" ]]; then
  print -u2 "Could not resolve both stereo-pair groups"
  exit 1
fi

if [[ "$left_group" == "$right_group" ]]; then
  rpc "{\"id\":$(next_id),\"jsonrpc\":\"2.0\",\"method\":\"Group.SetClients\",\"params\":{\"id\":\"$left_group\",\"clients\":[\"$RIGHT_CLIENT_ID\"]}}" >/dev/null
  server_status="$(rpc "{\"id\":$(next_id),\"jsonrpc\":\"2.0\",\"method\":\"Server.GetStatus\"}")"
  left_group="$(group_for_client "$server_status" "$LEFT_CLIENT_ID")"
  right_group="$(group_for_client "$server_status" "$RIGHT_CLIENT_ID")"
fi

if [[ -z "$left_group" || -z "$right_group" ]]; then
  print -u2 "Could not resolve both stereo-pair groups"
  exit 1
fi

if [[ "$(stream_for_group "$server_status" "$left_group")" != "LeftAudio" ]]; then
  rpc "{\"id\":$(next_id),\"jsonrpc\":\"2.0\",\"method\":\"Group.SetStream\",\"params\":{\"id\":\"$left_group\",\"stream_id\":\"LeftAudio\"}}" >/dev/null
fi

if [[ "$(stream_for_group "$server_status" "$right_group")" != "RightAudio" ]]; then
  rpc "{\"id\":$(next_id),\"jsonrpc\":\"2.0\",\"method\":\"Group.SetStream\",\"params\":{\"id\":\"$right_group\",\"stream_id\":\"RightAudio\"}}" >/dev/null
fi
