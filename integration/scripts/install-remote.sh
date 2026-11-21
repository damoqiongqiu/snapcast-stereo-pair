#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config
require_pair_config
compute_pair_roles
remote="$REMOTE_USER@$REMOTE_HOST"

if [[ ! -x "$repo_root/.build/bin/snapclient" ]]; then
  "$repo_root/integration/scripts/build-macos.sh"
fi

remote_home="$(ssh "$remote" 'print -r -- "$HOME"')"
remote_brew_bin="$(ssh "$remote" '
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  brew --prefix
')/bin"
rendered_plist="$(mktemp)"
trap 'rm -f "$rendered_plist"' EXIT
PAIR_RENDER_HOME="$remote_home" \
PAIR_RENDER_HOMEBREW_BIN="$remote_brew_bin" \
render_pair_template \
  "$repo_root/integration/launchagents/remote-client.plist.in" \
  "$rendered_plist"

ssh "$remote" 'mkdir -p "$HOME/Library/Application Support/Snapcast/bin" "$HOME/Library/Logs/Snapcast" "$HOME/Library/LaunchAgents"'
scp "$repo_root/.build/bin/snapclient" "$remote:Library/Application Support/Snapcast/bin/snapclient"
scp "$repo_root/.build/bin/set-audio-volume" "$remote:Library/Application Support/Snapcast/bin/set-audio-volume"
scp "$rendered_plist" "$remote:Library/LaunchAgents/com.snapcast.remote-client.plist"

ssh "$remote" env REMOTE_OUTPUT_DEVICE_UID="$REMOTE_OUTPUT_DEVICE_UID" zsh -s <<'REMOTE_SCRIPT'
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/snapclient"
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/set-audio-volume"
  "$HOME/Library/Application Support/Snapcast/bin/set-audio-volume" set "$REMOTE_OUTPUT_DEVICE_UID" 100
  uid="$(id -u)"
  launchctl bootout "gui/$uid/com.snapcast.remote-client" 2>/dev/null || true
  sleep 1
  launchctl bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/com.snapcast.remote-client.plist"
REMOTE_SCRIPT

print "Installed remote Snapcast client on $remote."
