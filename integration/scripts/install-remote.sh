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
rendered_remote_mode="$(mktemp)"
remote_control_json="$(mktemp)"
trap 'rm -f "$rendered_client_plist" "$rendered_wake_plist" "$rendered_wake_script" "$rendered_remote_mode" "$remote_control_json"' EXIT
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
PAIR_RENDER_HOME="$remote_home" \
PAIR_RENDER_HOMEBREW_BIN="$remote_brew_bin" \
render_pair_template \
  "$repo_root/integration/scripts/remote-mode.sh" \
  "$rendered_remote_mode"

ssh "$remote" 'mkdir -p "$HOME/Library/Application Support/Snapcast/bin" "$HOME/Library/Logs/Snapcast" "$HOME/Library/LaunchAgents"'
scp "$repo_root/.build/bin/snapclient" "$remote:Library/Application Support/Snapcast/bin/snapclient"
scp "$repo_root/.build/bin/set-audio-volume" "$remote:Library/Application Support/Snapcast/bin/set-audio-volume"
scp "$repo_root/.build/bin/wake-recovery-listener" "$remote:Library/Application Support/Snapcast/bin/wake-recovery-listener"
scp "$repo_root/integration/scripts/health-marker.sh" "$remote:Library/Application Support/Snapcast/health-marker.sh"
scp "$repo_root/integration/scripts/audio-profile.sh" "$remote:Library/Application Support/Snapcast/audio-profile.sh"
scp "$rendered_client_plist" "$remote:Library/LaunchAgents/com.snapcast.remote-client.plist"
scp "$rendered_wake_plist" "$remote:Library/LaunchAgents/com.snapcast.remote-wake-recovery.plist"
scp "$rendered_wake_script" "$remote:Library/Application Support/Snapcast/wake-recovery-remote.sh"
scp "$rendered_remote_mode" "$remote:Library/Application Support/Snapcast/remote-mode.sh"

ssh "$remote" zsh -s <<'REMOTE_SCRIPT'
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/snapclient"
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/set-audio-volume"
  chmod 755 "$HOME/Library/Application Support/Snapcast/bin/wake-recovery-listener"
  chmod 755 "$HOME/Library/Application Support/Snapcast/wake-recovery-remote.sh"
  chmod 755 "$HOME/Library/Application Support/Snapcast/remote-mode.sh"
  chmod 755 "$HOME/Library/Application Support/Snapcast/health-marker.sh"
  chmod 755 "$HOME/Library/Application Support/Snapcast/audio-profile.sh"
  ln -sfn "$HOME/Library/Application Support/Snapcast/remote-mode.sh" "$HOME/.snapcast-remote-mode"
  "$HOME/Library/Application Support/Snapcast/remote-mode.sh" snapcast
REMOTE_SCRIPT

local_state_dir="$HOME/Library/Application Support/Snapcast/state"
mkdir -p "$local_state_dir"
chmod 700 "$local_state_dir"
jq -n \
  --arg user "$REMOTE_USER" \
  --arg host "$REMOTE_HOST" \
  --arg helperPath "$remote_home/.snapcast-remote-mode" \
  '{user: $user, host: $host, helperPath: $helperPath}' \
  > "$remote_control_json"
install -m 600 "$remote_control_json" "$local_state_dir/remote-control.json"

print "Installed remote Snapcast client on $remote."
