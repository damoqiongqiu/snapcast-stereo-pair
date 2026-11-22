#!/bin/zsh

installation_support_dir() {
  print -r -- "${SNAPCAST_SUPPORT_DIR:-$HOME/Library/Application Support/Snapcast}"
}

installation_app_path() {
  print -r -- "${SNAPCAST_APP_PATH:-$HOME/Applications/MacBook Stereo Pair.app}"
}

installation_launch_dir() {
  print -r -- "${SNAPCAST_LAUNCH_DIR:-$HOME/Library/LaunchAgents}"
}

installation_manifest_path() {
  print -r -- "$(installation_support_dir)/state/installation.json"
}

installation_product_version() {
  local lifecycle_repo_root
  lifecycle_repo_root="$(cd "$(dirname "${(%):-%x}")/../.." && pwd)"
  local plist="${SNAPCAST_PRODUCT_PLIST:-$lifecycle_repo_root/native/Packaging/MacStereoPair-Info.plist}"
  plutil -extract CFBundleShortVersionString raw "$plist"
}

installation_lifecycle_action() {
  local manifest_version="$1"
  local manifest_digest="$2"
  local current_version="$3"
  local current_digest="$4"
  local assets_ok="$5"
  local force="$6"

  if [[ "$force" == "true" ]]; then
    print "force"
  elif [[ -z "$manifest_version" ]]; then
    print "fresh"
  elif [[ "$manifest_version" != "$current_version" ]]; then
    if (( $(installation_version_compare "$current_version" "$manifest_version") < 0 )); then
      print "downgrade"
    else
      print "upgrade"
    fi
  elif [[ "$assets_ok" != "yes" || -z "$manifest_digest" || "$manifest_digest" != "$current_digest" ]]; then
    print "repair"
  else
    print "up-to-date"
  fi
}

installation_version_compare() {
  local lhs="$1"
  local rhs="$2"
  local -a left right
  left=("${(@s:.:)lhs}")
  right=("${(@s:.:)rhs}")
  local index left_part right_part
  for (( index = 1; index <= ${#left} || index <= ${#right}; index++ )); do
    left_part="${left[index]:-0}"
    right_part="${right[index]:-0}"
    if (( left_part < right_part )); then
      print -1
      return
    elif (( left_part > right_part )); then
      print 1
      return
    fi
  done
  print 0
}

installation_manifest_field() {
  local field="$1"
  local manifest
  manifest="$(installation_manifest_path)"
  [[ -f "$manifest" ]] || return 1
  jq -r --arg field "$field" '.[$field] // empty' "$manifest"
}

installation_required_assets_exist() {
  local support_dir app_path launch_dir
  support_dir="$(installation_support_dir)"
  app_path="$(installation_app_path)"
  launch_dir="$(installation_launch_dir)"
  local -a files=(
    "$app_path/Contents/MacOS/MacStereoPair"
    "$support_dir/bin/StereoPairAgent"
    "$support_dir/bin/mac-stereo-pairctl"
    "$support_dir/bin/snapserver"
    "$support_dir/bin/snapclient"
    "$support_dir/bin/set-audio-volume"
    "$support_dir/bin/wake-recovery-listener"
    "$support_dir/setup/native-setup-helper.sh"
    "$support_dir/setup/source-root"
    "$support_dir/state/audio-devices.json"
    "$support_dir/set-mode.sh"
    "$support_dir/ensure-pair-routing.sh"
    "$support_dir/audio-levels.sh"
    "$support_dir/route-audio.sh"
    "$support_dir/wake-recovery-local.sh"
    "$support_dir/health-marker.sh"
    "$support_dir/audio-profile.sh"
    "$launch_dir/com.snapcast.server.plist"
    "$launch_dir/com.snapcast.local-client.plist"
    "$launch_dir/com.snapcast.route.plist"
    "$launch_dir/com.snapcast.splitter.plist"
    "$launch_dir/com.snapcast.pairing.plist"
    "$launch_dir/com.snapcast.wake-recovery.plist"
    "$launch_dir/com.snapcast.control-agent.plist"
  )
  local file
  for file in "${files[@]}"; do
    [[ -f "$file" ]] || return 1
  done
  return 0
}

installation_asset_digest() {
  local support_dir app_path launch_dir
  support_dir="$(installation_support_dir)"
  app_path="$(installation_app_path)"
  launch_dir="$(installation_launch_dir)"
  local -a files=(
    "$app_path/Contents/MacOS/MacStereoPair"
    "$support_dir/bin/StereoPairAgent"
    "$support_dir/bin/mac-stereo-pairctl"
    "$support_dir/bin/snapserver"
    "$support_dir/bin/snapclient"
    "$support_dir/bin/set-audio-volume"
    "$support_dir/bin/wake-recovery-listener"
    "$support_dir/setup/native-setup-helper.sh"
    "$support_dir/set-mode.sh"
    "$support_dir/ensure-pair-routing.sh"
    "$support_dir/route-audio.sh"
    "$support_dir/audio-levels.sh"
    "$support_dir/wake-recovery-local.sh"
    "$support_dir/health-marker.sh"
    "$support_dir/audio-profile.sh"
    "$launch_dir/com.snapcast.server.plist"
    "$launch_dir/com.snapcast.local-client.plist"
    "$launch_dir/com.snapcast.route.plist"
    "$launch_dir/com.snapcast.splitter.plist"
    "$launch_dir/com.snapcast.pairing.plist"
    "$launch_dir/com.snapcast.wake-recovery.plist"
    "$launch_dir/com.snapcast.control-agent.plist"
  )
  local file
  for file in "${files[@]}"; do
    [[ -f "$file" ]] || return 1
  done
  local config_file remote_control audio_devices
  config_file="${PAIR_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/snapcast-stereo-pair/pair.env}"
  remote_control="$(installation_support_dir)/state/remote-control.json"
  audio_devices="$(installation_support_dir)/state/audio-devices.json"
  {
    for file in "${files[@]}"; do
      print -r -- "${file#$HOME/}"
      stat -f '%Lp' "$file"
      shasum -a 256 "$file" | awk '{print $1}'
    done
    for file in "$config_file" "$remote_control" "$audio_devices"; do
      if [[ -f "$file" ]]; then
        print -r -- "${file#$HOME/}"
        stat -f '%Lp' "$file"
        shasum -a 256 "$file" | awk '{print $1}'
      fi
    done
  } | shasum -a 256 | awk '{print $1}'
}

write_installation_manifest() {
  local product_version="$1"
  local protocol_version="$2"
  local installer="$3"
  local asset_digest="$4"
  local support_dir state_dir manifest temporary
  support_dir="$(installation_support_dir)"
  state_dir="$support_dir/state"
  manifest="$state_dir/installation.json"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  temporary="$(mktemp "$state_dir/.installation.XXXXXX")"
  jq -n \
    --arg productVersion "$product_version" \
    --arg installer "$installer" \
    --arg assetDigest "$asset_digest" \
    --arg installedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson protocolVersion "$protocol_version" \
    '{
      schemaVersion: 1,
      configSchemaVersion: 1,
      productVersion: $productVersion,
      protocolVersion: $protocolVersion,
      installer: $installer,
      assetDigest: $assetDigest,
      installedAt: $installedAt
    }' > "$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$manifest"
}

refresh_installation_manifest_digest() {
  local manifest product_version protocol_version installer asset_digest
  manifest="$(installation_manifest_path)"
  [[ -f "$manifest" ]] || return 0
  product_version="$(jq -r '.productVersion // empty' "$manifest")"
  protocol_version="$(jq -r '.protocolVersion // empty' "$manifest")"
  installer="$(jq -r '.installer // empty' "$manifest")"
  [[ -n "$product_version" && -n "$protocol_version" && -n "$installer" ]] || return 1
  asset_digest="$(installation_asset_digest)"
  write_installation_manifest \
    "$product_version" "$protocol_version" "$installer" "$asset_digest"
}

installation_acquire_lock() {
  local state_dir lock_file
  state_dir="$(installation_support_dir)/state"
  lock_file="$state_dir/install.lock"
  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  if mkdir "$lock_file" 2>/dev/null; then
    print -r -- "$$" > "$lock_file/pid"
    return 0
  fi
  local existing_pid
  existing_pid="$(cat "$lock_file/pid" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    print -u2 "Another installation is already running (PID $existing_pid)."
    return 1
  fi
  rm -rf "$lock_file"
  mkdir "$lock_file"
  print -r -- "$$" > "$lock_file/pid"
}

installation_release_lock() {
  local lock_file
  lock_file="$(installation_support_dir)/state/install.lock"
  [[ "$(cat "$lock_file/pid" 2>/dev/null || true)" == "$$" ]] || return 0
  rm -rf "$lock_file"
}

backup_installation_assets() {
  local backup_dir="$1"
  local support_dir app_path launch_dir config_file remote_control audio_devices
  support_dir="$(installation_support_dir)"
  app_path="$(installation_app_path)"
  launch_dir="$(installation_launch_dir)"
  config_file="${PAIR_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/snapcast-stereo-pair/pair.env}"
  remote_control="$support_dir/state/remote-control.json"
  audio_devices="$support_dir/state/audio-devices.json"
  mkdir -p "$backup_dir/bin" "$backup_dir/setup" "$backup_dir/scripts" "$backup_dir/launchagents"
  chmod 700 "$backup_dir"
  if [[ -d "$app_path" ]]; then
    ditto "$app_path" "$backup_dir/app"
  fi
  if [[ -d "$support_dir/bin" ]]; then
    ditto "$support_dir/bin" "$backup_dir/bin"
  fi
  if [[ -d "$support_dir/setup" ]]; then
    ditto "$support_dir/setup" "$backup_dir/setup"
  fi
  local script
  for script in set-mode.sh ensure-pair-routing.sh audio-levels.sh route-audio.sh wake-recovery-local.sh health-marker.sh audio-profile.sh; do
    [[ -f "$support_dir/$script" ]] && \
      install -m "$(stat -f '%Lp' "$support_dir/$script")" "$support_dir/$script" "$backup_dir/scripts/$script"
  done
  local label
  for label in server local-client route splitter pairing wake-recovery control-agent; do
    [[ -f "$launch_dir/com.snapcast.$label.plist" ]] && \
      install -m "$(stat -f '%Lp' "$launch_dir/com.snapcast.$label.plist")" \
        "$launch_dir/com.snapcast.$label.plist" "$backup_dir/launchagents/"
  done
  [[ -f "$config_file" ]] && install -m 600 "$config_file" "$backup_dir/pair.env"
  [[ -f "$remote_control" ]] && install -m 600 "$remote_control" "$backup_dir/remote-control.json"
  [[ -f "$audio_devices" ]] && install -m 600 "$audio_devices" "$backup_dir/audio-devices.json"
  [[ -f "$(installation_manifest_path)" ]] && \
    install -m 600 "$(installation_manifest_path)" "$backup_dir/installation.json"
}

restore_installation_assets() {
  local backup_dir="$1"
  [[ -d "$backup_dir" ]] || return 1
  local support_dir app_path launch_dir config_file remote_control audio_devices
  support_dir="$(installation_support_dir)"
  app_path="$(installation_app_path)"
  launch_dir="$(installation_launch_dir)"
  config_file="${PAIR_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/snapcast-stereo-pair/pair.env}"
  remote_control="$support_dir/state/remote-control.json"
  audio_devices="$support_dir/state/audio-devices.json"

  if [[ -d "$backup_dir/app" ]]; then
    rm -rf "$app_path"
    mkdir -p "${app_path:h}"
    ditto "$backup_dir/app" "$app_path"
  fi
  if [[ -d "$backup_dir/bin" ]]; then
    rm -rf "$support_dir/bin"
    ditto "$backup_dir/bin" "$support_dir/bin"
  fi
  if [[ -d "$backup_dir/setup" ]]; then
    rm -rf "$support_dir/setup"
    ditto "$backup_dir/setup" "$support_dir/setup"
  fi
  local script
  for script in set-mode.sh ensure-pair-routing.sh audio-levels.sh route-audio.sh wake-recovery-local.sh health-marker.sh audio-profile.sh; do
    if [[ -f "$backup_dir/scripts/$script" ]]; then
      install -m "$(stat -f '%Lp' "$backup_dir/scripts/$script")" \
        "$backup_dir/scripts/$script" "$support_dir/$script"
    fi
  done
  local label
  for label in server local-client route splitter pairing wake-recovery control-agent; do
    if [[ -f "$backup_dir/launchagents/com.snapcast.$label.plist" ]]; then
      install -m "$(stat -f '%Lp' "$backup_dir/launchagents/com.snapcast.$label.plist")" \
        "$backup_dir/launchagents/com.snapcast.$label.plist" \
        "$launch_dir/com.snapcast.$label.plist"
    fi
  done
  [[ -f "$backup_dir/pair.env" ]] && install -m 600 "$backup_dir/pair.env" "$config_file"
  [[ -f "$backup_dir/remote-control.json" ]] && \
    install -m 600 "$backup_dir/remote-control.json" "$remote_control"
  [[ -f "$backup_dir/audio-devices.json" ]] && \
    install -m 600 "$backup_dir/audio-devices.json" "$audio_devices"
  [[ -f "$backup_dir/installation.json" ]] && \
    install -m 600 "$backup_dir/installation.json" "$(installation_manifest_path)"
}
