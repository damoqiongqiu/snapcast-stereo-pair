#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/integration/scripts/install-lifecycle.sh"

[[ "$(installation_lifecycle_action "" "" 0.2.0 digest yes false)" == "fresh" ]]
[[ "$(installation_lifecycle_action 0.2.0 digest 0.2.0 digest yes false)" == "up-to-date" ]]
[[ "$(installation_lifecycle_action 0.2.0 digest 0.2.0 digest no false)" == "repair" ]]
[[ "$(installation_lifecycle_action 0.2.0 old-digest 0.2.0 new-digest yes false)" == "repair" ]]
[[ "$(installation_lifecycle_action 0.2.0 digest 0.3.0 digest yes false)" == "upgrade" ]]
[[ "$(installation_lifecycle_action 0.3.0 digest 0.2.0 digest yes false)" == "downgrade" ]]
[[ "$(installation_lifecycle_action 0.2.0 digest 0.2.0 digest yes true)" == "force" ]]

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
export SNAPCAST_SUPPORT_DIR="$tmp_dir/support"
export SNAPCAST_APP_PATH="$tmp_dir/app/MacBook Stereo Pair.app"
export SNAPCAST_LAUNCH_DIR="$tmp_dir/launch"
mkdir -p \
  "$SNAPCAST_SUPPORT_DIR/bin" \
  "$SNAPCAST_SUPPORT_DIR/setup" \
  "$SNAPCAST_APP_PATH/Contents/MacOS" \
  "$SNAPCAST_LAUNCH_DIR"

for file in \
  "$SNAPCAST_APP_PATH/Contents/MacOS/MacStereoPair" \
  "$SNAPCAST_SUPPORT_DIR/bin/StereoPairAgent" \
  "$SNAPCAST_SUPPORT_DIR/bin/mac-stereo-pairctl" \
  "$SNAPCAST_SUPPORT_DIR/bin/snapserver" \
  "$SNAPCAST_SUPPORT_DIR/bin/snapclient" \
  "$SNAPCAST_SUPPORT_DIR/bin/set-audio-volume" \
  "$SNAPCAST_SUPPORT_DIR/bin/wake-recovery-listener" \
  "$SNAPCAST_SUPPORT_DIR/setup/native-setup-helper.sh" \
  "$SNAPCAST_SUPPORT_DIR/setup/source-root" \
  "$SNAPCAST_SUPPORT_DIR/set-mode.sh" \
  "$SNAPCAST_SUPPORT_DIR/ensure-pair-routing.sh" \
  "$SNAPCAST_SUPPORT_DIR/audio-levels.sh" \
  "$SNAPCAST_SUPPORT_DIR/route-audio.sh" \
  "$SNAPCAST_SUPPORT_DIR/wake-recovery-local.sh" \
  "$SNAPCAST_SUPPORT_DIR/health-marker.sh" \
  "$SNAPCAST_LAUNCH_DIR/com.snapcast.server.plist" \
  "$SNAPCAST_LAUNCH_DIR/com.snapcast.local-client.plist" \
  "$SNAPCAST_LAUNCH_DIR/com.snapcast.route.plist" \
  "$SNAPCAST_LAUNCH_DIR/com.snapcast.splitter.plist" \
  "$SNAPCAST_LAUNCH_DIR/com.snapcast.pairing.plist" \
  "$SNAPCAST_LAUNCH_DIR/com.snapcast.wake-recovery.plist" \
  "$SNAPCAST_LAUNCH_DIR/com.snapcast.control-agent.plist"; do
  print -r -- "$file" > "$file"
done

export PAIR_CONFIG_FILE="$tmp_dir/pair.env"
print -r -- 'LEFT_IS_REMOTE="true"' > "$PAIR_CONFIG_FILE"
digest="$(installation_asset_digest)"
write_installation_manifest 0.2.0 1 source "$digest"
[[ "$("$repo_root/integration/scripts/install-product.sh" --dry-run | awk -F= '$1=="action"{print $2}')" == "up-to-date" ]]
[[ "$("$repo_root/integration/scripts/install-product.sh" --force-reinstall --dry-run | awk -F= '$1=="action"{print $2}')" == "force" ]]
print -r -- 'LEFT_IS_REMOTE="false"' > "$PAIR_CONFIG_FILE"
[[ "$("$repo_root/integration/scripts/install-product.sh" --dry-run | awk -F= '$1=="action"{print $2}')" == "repair" ]]
print -r -- 'LEFT_IS_REMOTE="true"' > "$PAIR_CONFIG_FILE"
write_installation_manifest 0.1.0 1 source "$digest"
[[ "$("$repo_root/integration/scripts/install-product.sh" --dry-run | awk -F= '$1=="action"{print $2}')" == "upgrade" ]]
write_installation_manifest 0.3.0 1 source "$digest"
[[ "$("$repo_root/integration/scripts/install-product.sh" --dry-run | awk -F= '$1=="action"{print $2}')" == "downgrade" ]]

backup_dir="$tmp_dir/backup"
backup_installation_assets "$backup_dir"
print -r -- "changed" > "$SNAPCAST_SUPPORT_DIR/bin/StereoPairAgent"
print -r -- "changed" > "$SNAPCAST_APP_PATH/Contents/MacOS/MacStereoPair"
restore_installation_assets "$backup_dir"
grep -q "StereoPairAgent" "$SNAPCAST_SUPPORT_DIR/bin/StereoPairAgent"
grep -q "MacStereoPair" "$SNAPCAST_APP_PATH/Contents/MacOS/MacStereoPair"

mkdir -p "$tmp_dir/bin"
cat > "$tmp_dir/bin/launchctl" <<'EOF'
#!/bin/zsh
exit 0
EOF
cat > "$tmp_dir/fake-native-install.sh" <<EOF
#!/bin/zsh
print -r -- changed > "$SNAPCAST_SUPPORT_DIR/bin/StereoPairAgent"
print -r -- changed > "$SNAPCAST_APP_PATH/Contents/MacOS/MacStereoPair"
EOF
cat > "$tmp_dir/fake-local-install.sh" <<'EOF'
#!/bin/zsh
exit 1
EOF
cat > "$SNAPCAST_SUPPORT_DIR/set-mode.sh" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod 755 "$tmp_dir/bin/launchctl" "$tmp_dir/fake-native-install.sh" \
  "$tmp_dir/fake-local-install.sh" "$SNAPCAST_SUPPORT_DIR/set-mode.sh"
write_installation_manifest 0.1.0 1 source "$digest"
set +e
PATH="$tmp_dir/bin:$PATH" \
SNAPCAST_INSTALL_NATIVE_SCRIPT="$tmp_dir/fake-native-install.sh" \
SNAPCAST_INSTALL_LOCAL_SCRIPT="$tmp_dir/fake-local-install.sh" \
  "$repo_root/integration/scripts/install-product.sh" >/dev/null 2>&1
install_status=$?
set -e
[[ "$install_status" -ne 0 ]]
grep -q "StereoPairAgent" "$SNAPCAST_SUPPORT_DIR/bin/StereoPairAgent"
grep -q "MacStereoPair" "$SNAPCAST_APP_PATH/Contents/MacOS/MacStereoPair"

print "Install lifecycle tests passed"
