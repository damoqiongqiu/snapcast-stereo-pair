#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/pgrep" <<'EOF'
#!/bin/zsh
[[ -f "$APP_LIFECYCLE_RUNNING_FILE" ]]
EOF
cat > "$fake_bin/osascript" <<'EOF'
#!/bin/zsh
print -r -- "quit $*" >> "$APP_LIFECYCLE_LOG"
rm -f "$APP_LIFECYCLE_RUNNING_FILE"
EOF
cat > "$fake_bin/pkill" <<'EOF'
#!/bin/zsh
print -r -- "term $*" >> "$APP_LIFECYCLE_LOG"
EOF
cat > "$fake_bin/open" <<'EOF'
#!/bin/zsh
print -r -- "open $*" >> "$APP_LIFECYCLE_LOG"
EOF
chmod +x "$fake_bin/pgrep" "$fake_bin/osascript" "$fake_bin/pkill" "$fake_bin/open"

lifecycle_app="$tmp_dir/Running.app"
export APP_LIFECYCLE_RUNNING_FILE="$tmp_dir/running"
export APP_LIFECYCLE_LOG="$tmp_dir/lifecycle.log"
export SNAPCAST_APP_PATH="$lifecycle_app"
export SNAPCAST_PGREP_BIN="$fake_bin/pgrep"
export SNAPCAST_OSASCRIPT_BIN="$fake_bin/osascript"
export SNAPCAST_PKILL_BIN="$fake_bin/pkill"
export SNAPCAST_OPEN_BIN="$fake_bin/open"
print running > "$APP_LIFECYCLE_RUNNING_FILE"
source "$repo_root/integration/scripts/app-lifecycle.sh"
stop_running_app
[[ "$app_was_running" == "true" ]]
start_app_if_running
grep -Fq "quit" "$APP_LIFECYCLE_LOG"
grep -Fq "open $lifecycle_app" "$APP_LIFECYCLE_LOG"

: > "$APP_LIFECYCLE_LOG"
stop_running_app
start_app_if_running
[[ ! -s "$APP_LIFECYCLE_LOG" ]]

app="$tmp_dir/MacBook Stereo Pair.app"
set +e
"$repo_root/native/Packaging/build-app.sh" --output "$tmp_dir/unsafe-output" >/dev/null 2>&1
unsafe_status=$?
set -e
[[ "$unsafe_status" -ne 0 ]]

"$repo_root/native/Packaging/build-app.sh" --output "$app" >/dev/null

[[ -x "$app/Contents/MacOS/MacStereoPair" ]]
[[ "$(plutil -extract LSUIElement raw "$app/Contents/Info.plist")" == "false" ]]
[[ "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" == "AppIcon" ]]
[[ -f "$app/Contents/Resources/AppIcon.icns" ]]
resource_bundle="$app/Contents/Resources/MacStereoPairNative_MacStereoPair.bundle"
[[ -f "$resource_bundle/Contents/Resources/en.lproj/Localizable.strings" ]]
[[ -f "$resource_bundle/Contents/Resources/zh-Hans.lproj/Localizable.strings" ]]
codesign --verify --deep --strict "$app"

print "Native app packaging tests passed"
