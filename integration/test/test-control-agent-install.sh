#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/home" "$tmp_dir/bin"
cat > "$tmp_dir/bin/launchctl" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod 755 "$tmp_dir/bin/launchctl"

PATH="$tmp_dir/bin:$PATH" HOME="$tmp_dir/home" \
  "$repo_root/integration/scripts/install-native.sh" >/dev/null

support_dir="$tmp_dir/home/Library/Application Support/Snapcast"
launch_plist="$tmp_dir/home/Library/LaunchAgents/com.snapcast.control-agent.plist"
app="$tmp_dir/home/Applications/MacBook Stereo Pair.app"

[[ -x "$support_dir/bin/StereoPairAgent" ]]
[[ -x "$support_dir/bin/mac-stereo-pairctl" ]]
[[ -x "$support_dir/setup/native-setup-helper.sh" ]]
[[ -f "$support_dir/setup/source-root" ]]
[[ "$(stat -f '%Lp' "$support_dir/setup/source-root")" == "600" ]]
[[ -f "$launch_plist" ]]
plutil -lint "$launch_plist" >/dev/null
[[ -x "$app/Contents/MacOS/MacStereoPair" ]]
codesign --verify --deep --strict "$app"

print "Control Agent install tests passed"
