#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
target="${SNAPCAST_DEPLOYMENT_TARGET:-13.0}"
build_dir="${SNAPCAST_BUILD_DIR:-$repo_root/.build}"
binaries=(
  "$build_dir/bin/snapserver"
  "$build_dir/bin/snapclient"
  "$build_dir/bin/capture-blackhole"
  "$build_dir/bin/set-audio-volume"
  "$build_dir/bin/wake-recovery-listener"
)

normalize_version() {
  print -r -- "$1" | awk -F. '{ printf "%04d%04d%04d", $1, $2, $3 }'
}

minimum_macos() {
  otool -l "$1" | awk '
    /LC_BUILD_VERSION/ { build = 1; next }
    build && /minos/ { print $2; exit }
    /LC_VERSION_MIN_MACOSX/ { legacy = 1; next }
    legacy && /version/ { print $2; exit }
  '
}

target_key="$(normalize_version "$target")"
failed=0
for binary in "${binaries[@]}"; do
  if [[ ! -x "$binary" ]]; then
    print -u2 "Missing build artifact: $binary"
    failed=1
    continue
  fi
  binary_min="$(minimum_macos "$binary")"
  if [[ -n "$binary_min" ]] && (( $(normalize_version "$binary_min") > target_key )); then
    print -u2 "Binary targets macOS $binary_min, target $target: $binary"
    failed=1
  fi
  while IFS= read -r dependency; do
    [[ "$dependency" == /* ]] || continue
    [[ "$dependency" == /System/* || "$dependency" == /usr/lib/* ]] && continue
    [[ -e "$dependency" ]] || continue
    dependency_min="$(minimum_macos "$dependency")"
    [[ -n "$dependency_min" ]] || continue
    if (( $(normalize_version "$dependency_min") > target_key )); then
      print -u2 "Incompatible dependency: $dependency (minimum macOS $dependency_min, target $target)"
      failed=1
    fi
  done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}')
done

exit "$failed"
