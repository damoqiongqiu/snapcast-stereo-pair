#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/integration/scripts/pair-config.sh"

config_file="$(pair_config_default_path)"
mode="${1:-}"
if [[ -f "$config_file" && "$mode" != "--force" && "$mode" != "--print" ]]; then
  print "Configuration already exists: $config_file"
  print "Use --force to replace it."
  exit 0
fi

if [[ "${PAIR_NONINTERACTIVE:-0}" == "1" ]]; then
  load_pair_config
else
  load_pair_config
  read -r "REMOTE_USER?Remote SSH user: "
  read -r "REMOTE_HOST?Remote Mac IP or hostname: "
  read -r "SOURCE_HOST?Source Mac IP or hostname (blank for auto): "
  read -r "LEFT_IS_REMOTE?Is the remote Mac physically on the left? [true/false] (true): "
  [[ -n "$LEFT_IS_REMOTE" ]] || LEFT_IS_REMOTE=true
fi

if [[ -z "$SOURCE_HOST" ]]; then
  SOURCE_HOST="$(detect_source_host || true)"
fi
require_pair_config
compute_pair_roles

if [[ "$mode" == "--print" ]]; then
  print "REMOTE_USER=\"$REMOTE_USER\""
  print "REMOTE_HOST=\"$REMOTE_HOST\""
  print "SOURCE_HOST=\"$SOURCE_HOST\""
  print "LEFT_IS_REMOTE=\"$LEFT_IS_REMOTE\""
  print "CAPTURE_DEVICE=\"$CAPTURE_DEVICE\""
  print "LOCAL_OUTPUT_DEVICE=\"$LOCAL_OUTPUT_DEVICE\""
  print "NATIVE_OUTPUT_DEVICE_UID=\"$NATIVE_OUTPUT_DEVICE_UID\""
  print "LOCAL_CLIENT_ID=\"$LOCAL_CLIENT_ID\""
  print "REMOTE_CLIENT_ID=\"$REMOTE_CLIENT_ID\""
  print "LEFT_CLIENT_ID=\"$LEFT_CLIENT_ID\""
  print "RIGHT_CLIENT_ID=\"$RIGHT_CLIENT_ID\""
  exit 0
fi

save_pair_config
print "Wrote $config_file"
print "Left client:  $LEFT_CLIENT_ID"
print "Right client: $RIGHT_CLIENT_ID"
