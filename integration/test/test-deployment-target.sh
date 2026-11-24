#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

set +e
output="$(SNAPCAST_BUILD_DIR="$tmp_dir/empty-build" \
  "$repo_root/integration/scripts/check-deployment-target.sh" 2>&1)"
exit_code=$?
set -e

[[ "$exit_code" -ne 0 ]]
[[ "$output" == *"Missing build artifact"* ]]

print "Deployment target test passed"
