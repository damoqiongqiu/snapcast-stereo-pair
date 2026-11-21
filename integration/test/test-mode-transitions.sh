#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

swift test --package-path "$repo_root/native" --filter ModeCoordinatorTests
zsh -n "$repo_root/integration/scripts/set-mode.sh"
zsh -n "$repo_root/integration/scripts/remote-mode.sh"

source "$repo_root/integration/scripts/pair-config.sh"
REMOTE_USER=tester
REMOTE_HOST=192.0.2.10
LEFT_IS_REMOTE=true
load_pair_config
compute_pair_roles
PAIR_RENDER_HOMEBREW_BIN="$tmp_dir/homebrew/bin" \
render_pair_template \
  "$repo_root/integration/scripts/remote-mode.sh" \
  "$tmp_dir/remote-mode.sh"
zsh -n "$tmp_dir/remote-mode.sh"
[[ "$(grep -c '@[A-Z_]*@' "$tmp_dir/remote-mode.sh")" -eq 0 ]]
grep -Fq "$tmp_dir/homebrew/bin/SwitchAudioSource" "$tmp_dir/remote-mode.sh"

print "Mode transition tests passed"
