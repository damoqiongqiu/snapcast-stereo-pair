#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
native_installer="${SNAPCAST_INSTALL_NATIVE_SCRIPT:-$repo_root/integration/scripts/install-native.sh}"
local_installer="${SNAPCAST_INSTALL_LOCAL_SCRIPT:-$repo_root/integration/scripts/install-local.sh}"
source "$repo_root/integration/scripts/install-lifecycle.sh"
source "$repo_root/integration/scripts/pair-config.sh"

force_reinstall=false
dry_run=false
while (( $# > 0 )); do
  case "$1" in
    --force-reinstall)
      force_reinstall=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    *)
      print -u2 "Usage: $0 [--force-reinstall] [--dry-run]"
      exit 2
      ;;
  esac
done

product_version="$(installation_product_version)"
manifest_version="$(installation_manifest_field productVersion || true)"
manifest_digest="$(installation_manifest_field assetDigest || true)"
assets_ok="no"
current_digest=""
if installation_required_assets_exist; then
  assets_ok="yes"
  current_digest="$(installation_asset_digest)"
fi
action="$(installation_lifecycle_action \
  "$manifest_version" "$manifest_digest" \
  "$product_version" "$current_digest" \
  "$assets_ok" "$force_reinstall")"

if [[ "$dry_run" == "true" ]]; then
  print "action=$action"
  print "installedVersion=${manifest_version:-none}"
  print "availableVersion=$product_version"
  exit 0
fi

if [[ "$action" == "downgrade" ]]; then
  print -u2 "Installed version $manifest_version is newer than available version $product_version."
  print -u2 "Use --force-reinstall only if you intentionally want to downgrade."
  exit 1
fi

if [[ "$action" == "up-to-date" ]]; then
  print "MacBook Stereo Pair $product_version is already installed and verified."
  print "Use --force-reinstall to rebuild all program and service files."
  exit 0
fi

installation_acquire_lock

state_dir="$(installation_support_dir)/state"
config_file="$(pair_config_default_path)"
backup_dir="$state_dir/install-backups/$(date -u '+%Y%m%dT%H%M%SZ')-${manifest_version:-unknown}"
mkdir -p "$state_dir/install-backups"
chmod 700 "$state_dir/install-backups"
backup_installation_assets "$backup_dir"

uid="$(id -u)"
previous_mode="snapcast"
if [[ -f "$state_dir/audio-mode.json" ]]; then
  previous_mode="$(jq -r '.mode // "snapcast"' "$state_dir/audio-mode.json" 2>/dev/null || print snapcast)"
elif ! launchctl print "gui/$uid/com.snapcast.server" >/dev/null 2>&1; then
  previous_mode="system"
fi
installation_succeeded=false
cleanup_installation() {
  local exit_code=$?
  if [[ "$installation_succeeded" != "true" ]]; then
    print -u2 "Installation failed; restoring the previous program files."
    restore_installation_assets "$backup_dir" || true
    launchctl bootout "gui/$uid/com.snapcast.control-agent" 2>/dev/null || true
    if [[ -x "$(installation_support_dir)/set-mode.sh" ]]; then
      local restore_mode="snapcast"
      [[ "$previous_mode" == "system" ]] && restore_mode="native"
      "$(installation_support_dir)/set-mode.sh" "$restore_mode" >/dev/null 2>&1 || true
    fi
  fi
  installation_release_lock
  return "$exit_code"
}
trap cleanup_installation EXIT INT TERM

load_pair_config
if [[ -f "$config_file" ]]; then
  validate_pair_config_schema || {
    print -u2 "Configuration validation failed. No files were changed."
    exit 1
  }
  if ! grep -q '^CONFIG_SCHEMA=' "$config_file"; then
    migrate_pair_config_schema
  fi
fi

print "Installation action: $action"
"$native_installer"

if require_pair_config 2>/dev/null; then
  "$local_installer"
else
  PAIR_LOCAL_ONLY=1 "$local_installer"
fi

asset_digest="$(installation_asset_digest)"
write_installation_manifest "$product_version" 1 "source" "$asset_digest"
installation_succeeded=true
print "Installed MacBook Stereo Pair $product_version ($action)."
print "User configuration was preserved."
