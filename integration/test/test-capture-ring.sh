#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

clang -O1 -Wall -Wextra -Werror \
  -I"$repo_root/integration/capture" \
  -o "$tmp_dir/capture-ring-harness" \
  "$repo_root/integration/test/capture_ring_harness.c" \
  "$repo_root/integration/capture/capture_ring.c"
"$tmp_dir/capture-ring-harness"
print "Capture ring tests passed"
