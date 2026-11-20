#!/bin/zsh
set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config
pair_config_available=false
if require_pair_config >/dev/null 2>&1; then
  pair_config_available=true
fi

api="${SNAPSERVER_HTTP:-http://127.0.0.1:1780}"
uid="$(id -u)"
health_status=0

print "System output: $(SwitchAudioSource -c -t output 2>/dev/null || print unknown)"
print "Local processes:"
pgrep -ifl 'snapserver|snapclient|snapcast-capture-blackhole' || print "  none"

for label in com.snapcast.server com.snapcast.splitter com.snapcast.local-client com.snapcast.pairing; do
  print "\n$label:"
  launchctl print "gui/$uid/$label" 2>/dev/null | rg 'state =|runs =|pid =' | head -3 || print "  not loaded"
done

server_status="$(curl -fsS "$api/jsonrpc" \
  -H 'Content-Type: application/json' \
  --data '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}')" || {
  print -u2 "Snapserver control API is unavailable at $api"
  exit 1
}

print "\nStreams:"
if print -r -- "$server_status" | jq -e '
  [.result.server.streams[]
    | select(.id == "LeftAudio" or .id == "RightAudio")
    | .uri.query.sampleformat]
  | sort == ["48000:24:1", "48000:24:1"]
' >/dev/null; then
  print "  LeftAudio / RightAudio: 48000:24:1"
else
  print -u2 "  stream formats are not both 48000:24:1"
  health_status=1
fi

left_client="$(print -r -- "$server_status" | jq -r '
  [.result.server.groups[]
    | select(.stream_id == "LeftAudio")
    | .clients[]
    | select(.connected)
    | .id]
  | sort
  | join(",")
')"
right_client="$(print -r -- "$server_status" | jq -r '
  [.result.server.groups[]
    | select(.stream_id == "RightAudio")
    | .clients[]
    | select(.connected)
    | .id]
  | sort
  | join(",")
')"

print "  LeftAudio client: ${left_client:-none}"
print "  RightAudio client: ${right_client:-none}"
if [[ -z "$left_client" || -z "$right_client" ]]; then
  print -u2 "  each stream must have one connected client"
  health_status=1
elif [[ "$pair_config_available" == "true" &&
  ( "$left_client" != "$LEFT_CLIENT_ID" || "$right_client" != "$RIGHT_CLIENT_ID" ) ]]; then
  print -u2 "  pair routing is incorrect"
  health_status=1
elif [[ "$pair_config_available" != "true" ]]; then
  print "  expected role IDs unavailable; create pair.env for strict routing validation"
fi

print "\nRecent local issues:"
cutoff="$(/bin/date -v-2M '+%Y-%m-%d %H:%M:%S')"
recent_issues=0
for file in \
  "$HOME/Library/Logs/Snapcast/local-client.log" \
  "$HOME/Library/Logs/Snapcast/server.log" \
  "$HOME/Library/Logs/Snapcast/splitter.stderr.log" \
  "$HOME/Library/Logs/Snapcast/pairing.stderr.log"; do
  if [[ ! -f "$file" ]]; then
    continue
  fi
  matches="$(awk -v cutoff="$cutoff" '($1 " " $2) >= cutoff' "$file" |
    rg 'Not enough|age >|No chunk available|onResync' || true)"
  if [[ -n "$matches" ]]; then
    print -r -- "$matches"
    recent_issues=1
  fi
done
if [[ "$recent_issues" -eq 0 ]]; then
  print "  none"
else
  health_status=1
fi

exit "$health_status"
