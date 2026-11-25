#!/bin/zsh
set -euo pipefail

# Regression test for capture callback recovery. The FIFO clock remains
# continuous while CoreAudio callback stalls are recovered by the supervisor.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

harness="$tmp_dir/capture-recovery-harness"
clang -O1 -Wall -Wextra -Werror \
  -I"$repo_root/integration/capture" \
  -o "$harness" \
  "$repo_root/integration/test/capture_recovery_harness.c" \
  "$repo_root/integration/capture/capture_clock.c" \
  "$repo_root/integration/capture/capture_ring.c"
"$harness"

# Contract 5: wake-recovery helper binary (used by launchd) must be present
# after a build and reject invalid invocations with usage.
listener="$repo_root/.build/bin/wake-recovery-listener"
if [[ -x "$listener" ]]; then
  set +e
  usage="$("$listener" 2>&1)"
  listener_status=$?
  set -e
  [[ "$listener_status" -eq 2 && "$usage" == Usage:* ]] || {
    print -u2 "wake-recovery-listener usage contract broken"; exit 1; }
else
  print "Note: run build-macos.sh to verify wake-recovery-listener binary"
fi

# Contract 6: launchagent templates for wake recovery exist (both roles).
for plist in wake-recovery.plist.in remote-wake-recovery.plist.in; do
  [[ -f "$repo_root/integration/launchagents/$plist" ]] || {
    print -u2 "missing launchagent template: $plist"; exit 1; }
done

print "Watchdog recovery contract tests passed"
