#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
program="$repo_root/integration/scripts/health-status.jq"

valid='{"result":{"server":{"streams":[{"id":"LeftAudio","status":"playing","uri":{"query":{"sampleformat":"48000:24:1"}}},{"id":"RightAudio","status":"playing","uri":{"query":{"sampleformat":"48000:24:1"}}}]}}}'
idle='{"result":{"server":{"streams":[{"id":"LeftAudio","status":"idle","uri":{"query":{"sampleformat":"48000:24:1"}}},{"id":"RightAudio","status":"idle","uri":{"query":{"sampleformat":"48000:24:1"}}}]}}}'

print -r -- "$valid" | jq -f "$program" >/dev/null

set +e
output="$(print -r -- "$idle" | jq -f "$program" 2>&1)"
exit_code=$?
set -e

[[ "$exit_code" -ne 0 ]]
[[ "$output" == *"stream is idle"* ]]

print "Health check contract passed"
