#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config

uid="$(id -u)"

for label in com.snapcast.local-client com.snapcast.capture com.snapcast.server com.snapcast.route com.snapcast.splitter com.snapcast.pairing; do
  launchctl bootout "gui/$uid/$label" 2>/dev/null || true
done

SwitchAudioSource -u "$NATIVE_OUTPUT_DEVICE_UID" -t output || true
print "Snapcast services stopped and local speaker restored."
print "Files in ~/Library/Application Support/Snapcast were preserved."
