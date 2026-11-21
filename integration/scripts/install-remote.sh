#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/integration/scripts/pair-config.sh"
load_pair_config
require_pair_config
compute_pair_roles
remote="$REMOTE_USER@$REMOTE_HOST"

if [[ ! -x "$repo_root/.build/bin/snapclient" ||
  ! -x "$repo_root/.build/bin/set-audio-volume" ||
  ! -x "$repo_root/.build/bin/wake-recovery-listener" ]]; then
  "$repo_root/integration/scripts/build-macos.sh"
fi

remote_home="$(ssh "$remote" 'print -r -- "$HOME"')"
remote_brew_bin="$(ssh "$remote" '
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
  brew --prefix
')/bin"
rendered_client_plist="$(mktemp)"
rendered_wake_plist="$(mktemp)"
rendered_wake_script="$(mktemp)"
trap 'rm -f "$rendered_client_plist" "$rendered_wake_plist" "$rendered_wake_script"' EXIT
PAIR_RENDER_HOME="$remote_home" \
PAIR_RENDER_HOMEBREW_BIN="$remote_brew_bin" \
render_pair_template \
  "$repo_root/integration/launchagents/remote-client.plist.in" \
  "$rendered_client_plist"
PAIR_RENDER_HOME="$remote_home" \
PAIR_RENDER_HOMEBREW_BIN="$remote_brew_bin" \
render_pair_template \
  "$repo_root/integration/launchagents/remote-wake-recovery.plist.in" \
  "$rendered_wake_plist"
PAIR_RENDER_HOME="$remote_home" \
PAIR_RENDER_HOMEBREW_BIN="$remote_brew_bin" \
render_pair_template \
  "$repo_root/integration/scripts/wake-recovery-remote.sh" \
  "$rendered_wake_script"

ssh "$remote" 'mkdir -p "$HOME/Library/Application Support/Snapcast/bin" "$HOME/Library/Logs/Snapcast" "$HOME/Library/LaunchAgents"'
scp "$repo_root/.build/bin/snapclient" "$remote:Library/Application Support/Snapcast/bin/snapclient"
scp "$repo_root/.build/bin/set-audio-volume" "$remote:Library/Application Support/Snapcast/bin/set-audio-volume"
scp "$repo_root/.build/bin/wake-recovery-listener" "$remote:Library/Application Support/Snapcast/bin/wake-recovery-listener"
scp "$repo_root/integration/scripts/health-marker.sh" "$remote:Library/Application Support/Snapcast/health-marker.sh"
scp "$rendered_client_plist" "$remote:Library/LaunchAgents/com.snapcast.remote-client.plist"
scp "$rendered_wake_plist" "$remote:Library/LaunchAgents/com.snapcast.remote-wake-recovery.plist"
scp "$rendered_wake_script" "$remote:Library/Application Support/Snapcast/wake-recovery-remote.sh"

ssh "$remote" env REMOTE_OUTPUT_DEVICE_UID="$REMOTE_OUTPUT_DEVICE_UID" zsh -s <<'REMOTE_SCRIPT'
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/snapclient"
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/set-audio-volume"
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/wake-recovery-listener"
  chmod 755 "$HOME/Library/Application Support/Snapcast/wake-recovery-remote.sh"
  chmod 755 "$HOME/Library/Application Support/Snapcast/health-marker.sh"
  "$HOME/Library/Application Support/Snapcast/bin/set-audio-volume" set "$REMOTE_OUTPUT_DEVICE_UID" 100
  uid="$(id -u)"
  for label in com.snapcast.remote-client com.snapcast.remote-wake-recovery; do
    launchctl bootout "gui/$uid/$label" 2>/dev/null || true
  done
  sleep 1
  launchctl bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/com.snapcast.remote-client.plist"
  launchctl bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/com.snapcast.remote-wake-recovery.plist"
REMOTE_SCRIPT

print "Installed remote Snapcast client on $remote."
