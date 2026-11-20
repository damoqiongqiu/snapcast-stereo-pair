#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
ui_root="${SNAPWEB_SOURCE:-$repo_root/../snapweb-stereo-pair}"
support_dir="$HOME/Library/Application Support/Snapcast"
web_dir="$support_dir/snapweb"

if [[ ! -f "$ui_root/package.json" ]]; then
  print -u2 "Custom Snapweb source not found at: $ui_root"
  print -u2 "Clone snapcast/snapweb beside this repository or set SNAPWEB_SOURCE."
  exit 1
fi

(
  cd "$ui_root"
  npm ci
  npm run check
)

mkdir -p "$web_dir"
rsync -a --delete "$ui_root/dist/" "$web_dir/"
launchctl kickstart -k "gui/$(id -u)/com.snapcast.server"
print "Installed the MacBook stereo-pair interface at http://127.0.0.1:1780"
