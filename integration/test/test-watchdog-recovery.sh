#!/bin/zsh
set -euo pipefail

# Regression test for field-debugging-report.md issue #5:
# BlackHole device stall must be detected and recovered by the watchdog.
# Full runtime verification needs a live audio device; here we assert the
# source-level contract of the watchdog and the compiled helper binaries.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
capture_src="$repo_root/integration/capture/capture-blackhole-pa.c"

# Contract 1: watchdog thread is created and armed at startup.
for token in 'pthread_create(&watchdog_thread' 'capture_watchdog' 'g_last_read_ms' 'atomic_store'; do
  grep -q "$token" "$capture_src" || { print -u2 "watchdog missing: $token"; exit 1; }
done

# Contract 2: stall detection threshold is 1s, abort path uses Pa_AbortStream,
# and the escalation path exits with code 8 for launchd to relaunch.
grep -q 'now - last > 1000' "$capture_src" || { print -u2 "missing 1s stall threshold"; exit 1; }
grep -q 'Pa_AbortStream(g_capture_stream)' "$capture_src" || { print -u2 "missing abort path"; exit 1; }
grep -q '_exit(8)' "$capture_src" || { print -u2 "missing escalation exit code 8"; exit 1; }

# Contract 3: read loop refreshes the heartbeat on every successful frame
# and reopens the stream after a recoverable read error.
grep -q 'atomic_store(&g_last_read_ms, monotonic_ms())' "$capture_src" || {
  print -u2 "heartbeat not refreshed"; exit 1; }
grep -q 'Pa_OpenStream(&stream' "$capture_src" || { print -u2 "missing stream reopen"; exit 1; }

# Contract 4: C source still compiles after the patch (portaudio dev headers).
portaudio_prefix="$(/opt/homebrew/bin/brew --prefix portaudio 2>/dev/null || true)"
if [[ -n "$portaudio_prefix" && -d "$portaudio_prefix/include" ]]; then
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
  status=$?
  set -e
  [[ "$status" -eq 2 && "$usage" == Usage:* ]] || {
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
