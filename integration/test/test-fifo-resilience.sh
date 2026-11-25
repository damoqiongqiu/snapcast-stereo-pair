#!/bin/zsh
set -euo pipefail

# Regression test for field-debugging-report.md issue #4:
# FIFO reader close / pipe-full must not kill the capture process.
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

harness="$tmp_dir/fifo_write_harness"
clang -O1 -Wall -Wextra -I"$repo_root/integration/capture" \
  -o "$harness" "$repo_root/integration/test/fifo_write_harness.c"

# Case 1: non-blocking writer open on a FIFO with no reader must fail fast
# with ENXIO instead of blocking forever (open_fifo_writer relies on this).
fifo="$tmp_dir/no-reader.pcm"
mkfifo "$fifo"
if python3 - "$fifo" <<'PY'
import os, sys, errno
try:
    fd = os.open(sys.argv[1], os.O_WRONLY | os.O_NONBLOCK)
    os.close(fd)
    sys.exit(1)  # unexpected success
except OSError as e:
    sys.exit(0 if e.errno == errno.ENXIO else 2)
PY
then
  print "Case 1: non-blocking open fails fast with ENXIO (as expected)"
else
  print -u2 "Case 1 failed: expected ENXIO on non-blocking FIFO open"
  exit 1
fi

# Case 2: writeFully must survive a full pipe (EAGAIN) and a delayed reader,
# using poll(POLLOUT) to wait, then write all bytes without corruption.
fifo2="$tmp_dir/delayed-reader.pcm"
mkfifo "$fifo2"
"$harness" "$fifo2" 1048576

# Case 3: source-level contract checks for the resilience patch.
capture_src="$repo_root/integration/capture/capture-blackhole-pa.c"
fifo_header="$repo_root/integration/capture/fifo_io.h"
for token in 'captureClockNextBlock' 'coreAudioCaptureOpen' 'write_channel' \
  'open_fifo_writer' 'CAPTURE_WATCHDOG_RECOVER'; do
  grep -q "$token" "$capture_src" || { print -u2 "missing patched behavior: $token"; exit 1; }
done
grep -q 'Pa_ReadStream' "$capture_src" && {
  print -u2 "blocking PortAudio read must not remain in the capture path"; exit 1; }
grep -q '_exit(8)' "$capture_src" && {
  print -u2 "routine process relaunch must not remain in the capture path"; exit 1; }
grep -q 'poll(&pfd' "$fifo_header" || { print -u2 "missing EAGAIN poll handling"; exit 1; }
grep -q 'O_WRONLY | O_NONBLOCK' "$capture_src" || { print -u2 "missing non-blocking FIFO open"; exit 1; }

print "FIFO resilience tests passed"
