#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

clang -O2 -Wall -Wextra -Werror \
  -I"$repo_root/integration/capture" \
  -o "$tmp_dir/coreaudio-capture-harness" \
  "$repo_root/integration/test/coreaudio_capture_harness.c" \
  "$repo_root/integration/capture/capture_ring.c" \
  "$repo_root/integration/capture/coreaudio_capture.c" \
  -framework CoreAudio \
  -framework CoreFoundation
"$tmp_dir/coreaudio-capture-harness"
