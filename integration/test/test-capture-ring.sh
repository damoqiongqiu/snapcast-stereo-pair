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

clang -O1 -Wall -Wextra -Werror \
  -I"$repo_root/integration/capture" \
  -o "$tmp_dir/capture-clock-harness" \
  "$repo_root/integration/test/capture_clock_harness.c" \
  "$repo_root/integration/capture/capture_ring.c" \
  "$repo_root/integration/capture/capture_clock.c"
"$tmp_dir/capture-clock-harness"

link_libraries=()
if [[ "$(uname -s)" == "Linux" ]]; then
  link_libraries=(-lrt)
fi
clang -O1 -Wall -Wextra -Werror \
  -I"$repo_root/integration/capture" \
  -o "$tmp_dir/metrics-publish-harness" \
  "$repo_root/integration/test/metrics_publish_harness.c" \
  "$repo_root/integration/capture/audio_metrics.c" \
  "${link_libraries[@]}"
"$tmp_dir/metrics-publish-harness"
print "Capture ring and clock tests passed"
