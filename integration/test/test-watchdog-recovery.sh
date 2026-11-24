#!/bin/zsh
set -euo pipefail

# Regression test for field-debugging-report.md issue #5:
# BlackHole device stall must be detected and recovered by the watchdog.
# Full runtime verification needs a live audio device; here we assert the
# source-level contract of the watchdog and the compiled helper binaries.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
capture_src="$repo_root/integration/capture/capture-blackhole-pa.c"
portaudio_prefix="$(/opt/homebrew/bin/brew --prefix portaudio 2>/dev/null || true)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if [[ -n "$portaudio_prefix" && -d "$portaudio_prefix/include" ]]; then
  harness="$tmp_dir/watchdog-decision-harness"
  clang -O1 -Wall -Wextra \
    -I"$portaudio_prefix/include" \
    -I"$repo_root/integration/capture" \
    -o "$harness" \
    "$repo_root/integration/test/watchdog_decision_harness.c" \
    "$repo_root/integration/capture/capture_watchdog.c" \
    -L"$portaudio_prefix/lib" -lportaudio
  "$harness"
  clang -fsyntax-only -Wall -Wextra -I"$portaudio_prefix/include" \
    -I"$repo_root/integration/capture" "$capture_src"
else
  print "Note: portaudio headers unavailable, skipping compile check"
fi

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
