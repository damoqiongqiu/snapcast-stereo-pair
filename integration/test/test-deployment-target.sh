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

fixture_build="$tmp_dir/fixture-build"
fixture_bin="$fixture_build/bin"
fixture_source="$tmp_dir/fixture.c"
mkdir -p "$fixture_bin"
print -r -- 'int main(void) { return 0; }' > "$fixture_source"
clang -mmacosx-version-min=14.0 -o "$fixture_bin/snapserver" "$fixture_source"
for name in snapclient capture-blackhole set-audio-volume wake-recovery-listener; do
  ln -s snapserver "$fixture_bin/$name"
done

set +e
output="$(SNAPCAST_DEPLOYMENT_TARGET=13.0 \
  SNAPCAST_BUILD_DIR="$fixture_build" \
  "$repo_root/integration/scripts/check-deployment-target.sh" 2>&1)"
exit_code=$?
set -e

[[ "$exit_code" -ne 0 ]]
[[ "$output" == *"Binary targets macOS 14.0"* ]]

print "Deployment target test passed"
