#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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
