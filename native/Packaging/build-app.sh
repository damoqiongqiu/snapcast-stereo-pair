#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output="${1:-$repo_root/.build/MacBook Stereo Pair.app}"
temporary="${output}.tmp"

swift build --package-path "$repo_root/native" -c release --product MacStereoPair
rm -rf "$temporary"
mkdir -p "$temporary/Contents/MacOS"
cp "$repo_root/native/.build/release/MacStereoPair" "$temporary/Contents/MacOS/MacStereoPair"
cp "$repo_root/native/Packaging/MacStereoPair-Info.plist" "$temporary/Contents/Info.plist"
codesign --force --sign - "$temporary" >/dev/null
rm -rf "$output"
mv "$temporary" "$output"
print -r -- "$output"
