#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output="$repo_root/.build/MacBook Stereo Pair.app"
while (( $# > 0 )); do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || {
        print -u2 "Missing value for --output"
        exit 2
      }
      output="$2"
      shift 2
      ;;
    *)
      output="$1"
      shift
      ;;
  esac
done
[[ "$output" == *.app ]] || {
  print -u2 "Output must be an .app bundle path: $output"
  exit 2
}
[[ "$output" != "/" && "$output" != "$HOME" ]] || {
  print -u2 "Refusing unsafe output path: $output"
  exit 2
}
temporary="${output}.tmp"

swift build --package-path "$repo_root/native" -c release --product MacStereoPair
rm -rf "$temporary"
mkdir -p "$temporary/Contents/MacOS" "$temporary/Contents/Resources"
cp "$repo_root/native/.build/release/MacStereoPair" "$temporary/Contents/MacOS/MacStereoPair"
cp "$repo_root/native/Packaging/MacStereoPair-Info.plist" "$temporary/Contents/Info.plist"
resource_bundle="$repo_root/native/.build/release/MacStereoPairNative_MacStereoPair.bundle"
[[ -d "$resource_bundle" ]] || {
  print -u2 "Missing Swift package resource bundle: $resource_bundle"
  exit 1
}
cp -R "$resource_bundle" "$temporary/Contents/Resources/"
codesign --force --deep --sign - "$temporary" >/dev/null
rm -rf "$output"
mv "$temporary" "$output"
print -r -- "$output"
