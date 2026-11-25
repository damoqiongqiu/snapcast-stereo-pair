# BlackHole Capture Clock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blocking PortAudio capture path with a CoreAudio callback producer and a continuous 48 kHz FIFO clock so idle BlackHole periods never tear down the Snapcast stream.

**Architecture:** A real-time-safe HAL IOProc pushes stereo float frames into a lock-free SPSC ring. A writer thread emits exact 10 ms blocks from that ring or digital silence, keeping FIFO and Snapserver timelines continuous while a separate recovery loop restarts stalled CoreAudio callbacks.

**Tech Stack:** C11 atomics, CoreAudio HAL, existing FIFO and `S24In32` conversion helpers, shell integration tests, Swift metrics bridge.

**Spec:** `docs/designs/2026-11-25-blackhole-capture-clock-design.md`

## Global Constraints

- Audio format remains 48 kHz stereo float32 capture to dual mono `S24In32`.
- Writer blocks are exactly 480 frames every 10 ms.
- CoreAudio callbacks must not allocate, log, write files, or take blocking locks.
- Left and right output lengths must be identical on every writer cycle.
- Recovery starts after 2 seconds without a callback heartbeat.
- Process exit is a last resort after 15 seconds without recovery.
- No resampling or lossy codecs are introduced.
- Existing `CAPTURE_DEVICE` naming behavior remains as an override.
- Public releases remain compatible with macOS 13 and newer on Intel and Apple Silicon.

## Review Focus

- A callback delivering 512 frames must not leave partial-frame gaps or desynchronize left/right.
- A long idle period must generate silence rather than restart the process or reconnect FIFOs.
- A resumed producer must play fresh samples without replaying a stale backlog.
- A slow or missing FIFO reader must block only the writer and never the CoreAudio callback.
- A CoreAudio device that disappears, changes format, or stops callbacks must recover without affecting the writer clock.

---

### Task 1: Add the Lock-Free Capture Ring

**Files:**
- Create: `integration/capture/capture_ring.h`
- Create: `integration/capture/capture_ring.c`
- Create: `integration/test/capture_ring_harness.c`
- Create: `integration/test/test-capture-ring.sh`

**Interfaces:**
- Consumes: stereo float input blocks from the future CoreAudio IOProc.
- Produces:
  - `void captureFrameRingInit(CaptureFrameRing* ring)`
  - `size_t captureFrameRingAvailable(const CaptureFrameRing* ring)`
  - `bool captureFrameRingPushInterleaved(CaptureFrameRing*, const float*, size_t)`
  - `bool captureFrameRingPushPlanar(CaptureFrameRing*, const float*, const float*, size_t)`
  - `size_t captureFrameRingPop(CaptureFrameRing*, float*, size_t)`
  - `size_t captureFrameRingDiscard(CaptureFrameRing*, size_t)`

- [ ] **Step 1: Write the failing ring test**

Create `integration/test/capture_ring_harness.c` with:

```c
#include "capture_ring.h"

#include <math.h>
#include <stdio.h>

static int failures;

#define CHECK(condition, message)                                                \
    do                                                                          \
    {                                                                           \
        if (!(condition))                                                       \
        {                                                                       \
            fprintf(stderr, "%s\n", message);                                   \
            ++failures;                                                         \
        }                                                                       \
    } while (0)

int main(void)
{
    CaptureFrameRing ring;
    captureFrameRingInit(&ring);

    float interleaved[] = {0.25F, -0.25F, 0.5F, -0.5F};
    CHECK(captureFrameRingPushInterleaved(&ring, interleaved, 2), "push interleaved");
    CHECK(captureFrameRingAvailable(&ring) == 2, "two frames available");

    float output[4] = {0};
    CHECK(captureFrameRingPop(&ring, output, 2) == 2, "pop two frames");
    CHECK(output[0] == 0.25F && output[1] == -0.25F, "first frame preserved");
    CHECK(output[2] == 0.5F && output[3] == -0.5F, "second frame preserved");

    float left[] = {0.1F, 0.2F, 0.3F};
    float right[] = {-0.1F, -0.2F, -0.3F};
    CHECK(captureFrameRingPushPlanar(&ring, left, right, 3), "push planar");
    CHECK(captureFrameRingDiscard(&ring, 1) == 1, "discard one frame");
    CHECK(captureFrameRingPop(&ring, output, 1) == 1, "pop after discard");
    CHECK(fabsf(output[0] - 0.2F) < 0.0001F, "left after discard");
    CHECK(fabsf(output[1] + 0.2F) < 0.0001F, "right after discard");

    captureFrameRingInit(&ring);
    float full[CAPTURE_RING_FRAMES * 2];
    for (size_t i = 0; i < CAPTURE_RING_FRAMES * 2; ++i)
        full[i] = (float)i;
    CHECK(captureFrameRingPushInterleaved(&ring, full, CAPTURE_RING_FRAMES), "fill ring");
    CHECK(!captureFrameRingPushInterleaved(&ring, interleaved, 2), "reject overflow");
    CHECK(captureFrameRingAvailable(&ring) == CAPTURE_RING_FRAMES, "overflow preserves old frames");

    return failures == 0 ? 0 : 1;
}
```

Create `integration/test/test-capture-ring.sh` with:

```zsh
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
```

- [ ] **Step 2: Verify the test fails**

Run: `chmod +x integration/test/test-capture-ring.sh && integration/test/test-capture-ring.sh`

Expected: compilation fails because `capture_ring.h` does not exist.

- [ ] **Step 3: Implement the ring**

Create `integration/capture/capture_ring.h`:

```c
#pragma once

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define CAPTURE_CHANNELS 2
#define CAPTURE_RING_FRAMES 16384u

typedef struct
{
    float left[CAPTURE_RING_FRAMES];
    float right[CAPTURE_RING_FRAMES];
    atomic_uint_fast64_t write_frame;
    atomic_uint_fast64_t read_frame;
} CaptureFrameRing;

void captureFrameRingInit(CaptureFrameRing* ring);
size_t captureFrameRingAvailable(const CaptureFrameRing* ring);
bool captureFrameRingPushInterleaved(CaptureFrameRing* ring, const float* stereo, size_t frames);
bool captureFrameRingPushPlanar(CaptureFrameRing* ring, const float* left, const float* right, size_t frames);
size_t captureFrameRingPop(CaptureFrameRing* ring, float* stereo, size_t frames);
size_t captureFrameRingDiscard(CaptureFrameRing* ring, size_t frames);

#ifdef __cplusplus
}
#endif
```

Create `integration/capture/capture_ring.c`. Use monotonic 64-bit write/read
positions, acquire/release operations, and power-of-two masking:

```c
#define CAPTURE_RING_MASK (CAPTURE_RING_FRAMES - 1u)

size_t captureFrameRingAvailable(const CaptureFrameRing* ring)
{
    const uint64_t write = atomic_load_explicit(&ring->write_frame, memory_order_acquire);
    const uint64_t read = atomic_load_explicit(&ring->read_frame, memory_order_relaxed);
    return (size_t)(write - read);
}

bool captureFrameRingPushInterleaved(CaptureFrameRing* ring, const float* stereo, size_t frames)
{
    if ((ring == NULL) || (stereo == NULL) || frames == 0)
        return false;
    const uint64_t write = atomic_load_explicit(&ring->write_frame, memory_order_relaxed);
    const uint64_t read = atomic_load_explicit(&ring->read_frame, memory_order_acquire);
    if (frames > CAPTURE_RING_FRAMES - (size_t)(write - read))
        return false;
    for (size_t i = 0; i < frames; ++i)
    {
        const size_t position = (size_t)((write + i) & CAPTURE_RING_MASK);
        ring->left[position] = stereo[i * CAPTURE_CHANNELS];
        ring->right[position] = stereo[i * CAPTURE_CHANNELS + 1u];
    }
    atomic_store_explicit(&ring->write_frame, write + frames, memory_order_release);
    return true;
}
```

Implement planar push, pop, and discard with the same SPSC rules. `pop` copies
at most the requested frame count and returns the copied count.

- [ ] **Step 4: Verify the ring tests pass**

Run: `integration/test/test-capture-ring.sh`

Expected: `Capture ring tests passed`.

- [ ] **Step 5: Commit**

```bash
git add integration/capture/capture_ring.* integration/test/capture_ring_harness.c integration/test/test-capture-ring.sh
git commit -m "feat: add real-time capture frame ring"
```

---

### Task 2: Add Continuous Silence Clock Selection

**Files:**
- Create: `integration/capture/capture_clock.h`
- Create: `integration/capture/capture_clock.c`
- Create: `integration/test/capture_clock_harness.c`
- Modify: `integration/test/test-capture-ring.sh`

**Interfaces:**
- Consumes: `CaptureFrameRing` from Task 1.
- Produces:
  - `#define CAPTURE_BLOCK_FRAMES 480u`
  - `#define CAPTURE_MAX_BACKLOG_FRAMES 2400u`
  - `typedef struct { bool has_audio; size_t frames; size_t dropped_frames; } CaptureClockBlock`
  - `CaptureClockBlock captureClockNextBlock(CaptureFrameRing*, float*, size_t, size_t)`

- [ ] **Step 1: Write the failing clock test**

Create `integration/test/capture_clock_harness.c` with:

```c
#include "capture_clock.h"
#include "capture_ring.h"

#include <math.h>
#include <stdio.h>

static int failures;

#define CHECK(condition, message)                                                \
    do                                                                          \
    {                                                                           \
        if (!(condition))                                                       \
        {                                                                       \
            fprintf(stderr, "%s\n", message);                                   \
            ++failures;                                                         \
        }                                                                       \
    } while (0)

static void fill(float* stereo, size_t frames, float value)
{
    for (size_t i = 0; i < frames * 2; ++i)
        stereo[i] = value;
}

int main(void)
{
    CaptureFrameRing ring;
    captureFrameRingInit(&ring);
    float output[CAPTURE_BLOCK_FRAMES * 2];

    CaptureClockBlock silent = captureClockNextBlock(
        &ring, output, CAPTURE_BLOCK_FRAMES, CAPTURE_MAX_BACKLOG_FRAMES);
    CHECK(!silent.has_audio, "empty ring selects silence");
    CHECK(silent.frames == CAPTURE_BLOCK_FRAMES, "silence has exact block length");
    CHECK(output[0] == 0.0F && output[CAPTURE_BLOCK_FRAMES * 2 - 1] == 0.0F, "silence is zero");

    float real[CAPTURE_BLOCK_FRAMES * 2];
    fill(real, CAPTURE_BLOCK_FRAMES, 0.25F);
    CHECK(captureFrameRingPushInterleaved(&ring, real, CAPTURE_BLOCK_FRAMES), "push real block");
    CaptureClockBlock live = captureClockNextBlock(
        &ring, output, CAPTURE_BLOCK_FRAMES, CAPTURE_MAX_BACKLOG_FRAMES);
    CHECK(live.has_audio, "complete block selects real audio");
    CHECK(live.frames == CAPTURE_BLOCK_FRAMES, "real block has exact length");
    CHECK(fabsf(output[0] - 0.25F) < 0.0001F, "real block starts with newest data");

    captureFrameRingInit(&ring);
    float newest[CAPTURE_BLOCK_FRAMES * 2];
    fill(real, CAPTURE_BLOCK_FRAMES, 0.1F);
    fill(newest, CAPTURE_BLOCK_FRAMES, 0.9F);
    CHECK(captureFrameRingPushInterleaved(&ring, real, CAPTURE_BLOCK_FRAMES), "push stale block");
    CHECK(captureFrameRingPushInterleaved(&ring, newest, CAPTURE_BLOCK_FRAMES), "push newest block");
    CaptureClockBlock fresh = captureClockNextBlock(&ring, output, CAPTURE_BLOCK_FRAMES, CAPTURE_BLOCK_FRAMES);
    CHECK(fresh.has_audio, "fresh block selected after backlog trim");
    CHECK(fresh.dropped_frames == CAPTURE_BLOCK_FRAMES, "one stale block dropped");
    CHECK(fabsf(output[0] - 0.9F) < 0.0001F, "newest block survives trim");

    return failures == 0 ? 0 : 1;
}
```

Modify `integration/test/test-capture-ring.sh` to compile and run both harnesses
with `capture_ring.c` and `capture_clock.c`.

- [ ] **Step 2: Verify the test fails**

Run: `integration/test/test-capture-ring.sh`

Expected: compilation fails because `capture_clock.h` does not exist.

- [ ] **Step 3: Implement clock selection**

Create `integration/capture/capture_clock.h`:

```c
#pragma once

#include "capture_ring.h"

#include <stdbool.h>
#include <stddef.h>

#define CAPTURE_BLOCK_FRAMES 480u
#define CAPTURE_MAX_BACKLOG_FRAMES 2400u

typedef struct
{
    bool has_audio;
    size_t frames;
    size_t dropped_frames;
} CaptureClockBlock;

CaptureClockBlock captureClockNextBlock(
    CaptureFrameRing* ring, float* output, size_t frames, size_t max_backlog_frames);
```

Create `integration/capture/capture_clock.c`:

```c
CaptureClockBlock captureClockNextBlock(
    CaptureFrameRing* ring, float* output, size_t frames, size_t max_backlog_frames)
{
    CaptureClockBlock result = {.has_audio = false, .frames = frames, .dropped_frames = 0};
    if ((ring == NULL) || (output == NULL) || (frames == 0))
        return result;

    const size_t available = captureFrameRingAvailable(ring);
    if (available > max_backlog_frames && available > frames)
    {
        result.dropped_frames = captureFrameRingDiscard(ring, available - frames);
    }

    if (captureFrameRingAvailable(ring) < frames)
    {
        for (size_t i = 0; i < frames * CAPTURE_CHANNELS; ++i)
            output[i] = 0.0F;
        return result;
    }

    result.has_audio = captureFrameRingPop(ring, output, frames) == frames;
    if (!result.has_audio)
    {
        for (size_t i = 0; i < frames * CAPTURE_CHANNELS; ++i)
            output[i] = 0.0F;
    }
    return result;
}
```

- [ ] **Step 4: Verify ring and clock tests pass**

Run: `integration/test/test-capture-ring.sh`

Expected: `Capture ring and clock tests passed`.

- [ ] **Step 5: Commit**

```bash
git add integration/capture/capture_clock.* integration/test/capture_clock_harness.c integration/test/test-capture-ring.sh
git commit -m "feat: add continuous capture clock selection"
```

---

### Task 3: Replace Fatal Watchdog Semantics

**Files:**
- Modify: `integration/capture/capture_watchdog.h`
- Modify: `integration/capture/capture_watchdog.c`
- Modify: `integration/test/watchdog_decision_harness.c`
- Modify: `integration/test/test-watchdog-recovery.sh`

**Interfaces:**
- Consumes: monotonic milliseconds for callback heartbeat and recovery attempt.
- Produces:
  - `CAPTURE_WATCHDOG_NONE`
  - `CAPTURE_WATCHDOG_RECOVER`
  - `CAPTURE_WATCHDOG_EXIT_PROCESS`
  - `capture_watchdog_decide(long long now_ms, long long last_callback_ms)`
  - `capture_watchdog_should_attempt_recovery(long long now_ms, long long last_attempt_ms)`

- [ ] **Step 1: Change the failing watchdog tests**

Replace the decision assertions in `watchdog_decision_harness.c` with:

```c
expect_decision("fresh", capture_watchdog_decide(3999, 2000), CAPTURE_WATCHDOG_NONE);
expect_decision("idle within recovery deadline", capture_watchdog_decide(4001, 2000), CAPTURE_WATCHDOG_RECOVER);
expect_decision("recovery exhausted", capture_watchdog_decide(17001, 2000), CAPTURE_WATCHDOG_EXIT_PROCESS);

if (capture_watchdog_should_attempt_recovery(2500, 0))
{
    fprintf(stderr, "first recovery must be allowed immediately\n");
    ++failures;
}
if (!capture_watchdog_should_attempt_recovery(4500, 2000))
{
    fprintf(stderr, "recovery must be rate limited\n");
    ++failures;
}
```

Remove `CaptureStreamHandle` assertions because the helper no longer aborts a
PortAudio stream.

- [ ] **Step 2: Verify the test fails**

Run: `integration/test/test-watchdog-recovery.sh`

Expected: compilation fails because `CAPTURE_WATCHDOG_RECOVER` and
`capture_watchdog_should_attempt_recovery` do not exist.

- [ ] **Step 3: Implement non-fatal recovery decisions**

Update the enum in `capture_watchdog.h` to:

```c
typedef enum
{
    CAPTURE_WATCHDOG_NONE = 0,
    CAPTURE_WATCHDOG_RECOVER,
    CAPTURE_WATCHDOG_EXIT_PROCESS
} CaptureWatchdogDecision;
```

Implement:

```c
#define CAPTURE_CALLBACK_TIMEOUT_MS 2000
#define CAPTURE_RECOVERY_INTERVAL_MS 2000
#define CAPTURE_EXIT_TIMEOUT_MS 15000

CaptureWatchdogDecision capture_watchdog_decide(long long now_ms, long long last_callback_ms)
{
    if (last_callback_ms <= 0 || now_ms - last_callback_ms < CAPTURE_CALLBACK_TIMEOUT_MS)
        return CAPTURE_WATCHDOG_NONE;
    if (now_ms - last_callback_ms < CAPTURE_EXIT_TIMEOUT_MS)
        return CAPTURE_WATCHDOG_RECOVER;
    return CAPTURE_WATCHDOG_EXIT_PROCESS;
}

bool capture_watchdog_should_attempt_recovery(long long now_ms, long long last_attempt_ms)
{
    return last_attempt_ms <= 0 || now_ms - last_attempt_ms >= CAPTURE_RECOVERY_INTERVAL_MS;
}
```

Keep the existing stream helper code temporarily so the old binary still
builds until Task 5 removes it.

- [ ] **Step 4: Verify the lifecycle tests pass**

Run: `integration/test/test-watchdog-recovery.sh`

Expected: `Watchdog recovery contract tests passed`.

- [ ] **Step 5: Commit**

```bash
git add integration/capture/capture_watchdog.* integration/test/watchdog_decision_harness.c integration/test/test-watchdog-recovery.sh
git commit -m "fix: separate capture idle from fatal watchdog state"
```

---

### Task 4: Add the CoreAudio HAL Capture Backend

**Files:**
- Create: `integration/capture/coreaudio_capture.h`
- Create: `integration/capture/coreaudio_capture.c`
- Create: `integration/test/coreaudio_capture_harness.c`
- Create: `integration/test/test-coreaudio-capture.sh`

**Interfaces:**
- Consumes: `CaptureFrameRing` from Task 1.
- Produces:
  - `typedef struct CoreAudioCapture`
  - `int coreAudioCaptureOpen(CoreAudioCapture*, const char* requested_name, CaptureFrameRing*)`
  - `int coreAudioCaptureRestart(CoreAudioCapture*)`
  - `void coreAudioCaptureClose(CoreAudioCapture*)`
  - atomic heartbeat/callback/push-failure fields exposed in the struct

- [ ] **Step 1: Write the failing hardware harness**

Create `integration/test/coreaudio_capture_harness.c`:

```c
#include "coreaudio_capture.h"

#include <stdio.h>
#include <time.h>
#include <unistd.h>

static long long now_ms(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

int main(void)
{
    CaptureFrameRing ring;
    captureFrameRingInit(&ring);

    CoreAudioCapture missing;
    if (coreAudioCaptureOpen(&missing, "Definitely Missing Device", &ring) == 0)
    {
        fprintf(stderr, "missing device unexpectedly opened\n");
        return 1;
    }

    CoreAudioCapture capture;
    if (coreAudioCaptureOpen(&capture, "BlackHole", &ring) != 0)
    {
        fprintf(stderr, "BlackHole unavailable; hardware callback probe skipped\n");
        return 0;
    }

    const long long start = now_ms();
    while (now_ms() - start < 1200)
        usleep(20000);

    const unsigned long long callbacks =
        atomic_load_explicit(&capture.callback_count, memory_order_acquire);
    coreAudioCaptureClose(&capture);
    if (callbacks < 50)
    {
        fprintf(stderr, "expected continuous callbacks, got %llu\n", callbacks);
        return 1;
    }
    printf("CoreAudio callbacks=%llu\n", callbacks);
    return 0;
}
```

Create `integration/test/test-coreaudio-capture.sh` compiling:

```zsh
clang -O2 -Wall -Wextra -Werror \
  -I"$repo_root/integration/capture" \
  -o "$tmp_dir/coreaudio-capture-harness" \
  "$repo_root/integration/test/coreaudio_capture_harness.c" \
  "$repo_root/integration/capture/capture_ring.c" \
  "$repo_root/integration/capture/coreaudio_capture.c" \
  -framework CoreAudio \
  -framework CoreFoundation
```

- [ ] **Step 2: Verify the test fails**

Run: `chmod +x integration/test/test-coreaudio-capture.sh && integration/test/test-coreaudio-capture.sh`

Expected: compilation fails because `coreaudio_capture.h` does not exist.

- [ ] **Step 3: Implement the HAL backend**

Define these fields in `coreaudio_capture.h`:

```c
typedef struct
{
    AudioObjectID device_id;
    AudioDeviceIOProcID proc_id;
    CaptureFrameRing* ring;
    atomic_llong callback_ms;
    atomic_ullong callback_count;
    atomic_ullong push_failures;
    bool started;
} CoreAudioCapture;
```

In `coreaudio_capture.c`:

1. Enumerate `kAudioHardwarePropertyDevices`.
2. Read each `kAudioObjectPropertyName`.
3. Select the first device whose name contains `requested_name`; default to
   `BlackHole 2ch`.
4. Read input stream lists with `kAudioDevicePropertyStreams` on the input
   scope.
5. Read `kAudioStreamPropertyVirtualFormat`; require:
   - `mSampleRate == 48000`
   - `mChannelsPerFrame == 2`
   - `kAudioFormatLinearPCM`
   - `kAudioFormatFlagIsFloat`
6. Install `AudioDeviceCreateIOProcID(capture->device_id, capture_io_proc, capture, &capture->proc_id)`.
7. Call `AudioDeviceStart(capture->device_id, capture->proc_id)`.

The IOProc must:

```c
static OSStatus capture_io_proc(
    AudioObjectID device,
    const AudioTimeStamp* now,
    const AudioBufferList* input,
    const AudioTimeStamp* input_time,
    AudioBufferList* output,
    const AudioTimeStamp* output_time,
    void* context)
{
    CoreAudioCapture* capture = context;
    atomic_store_explicit(&capture->callback_ms, monotonic_ms(), memory_order_release);
    atomic_fetch_add_explicit(&capture->callback_count, 1, memory_order_relaxed);
    if ((input == NULL) || (input->mNumberBuffers == 0) || (input->mBuffers[0].mData == NULL))
        return noErr;

    bool pushed = false;
    if (input->mNumberBuffers == 1)
    {
        const size_t frames = input->mBuffers[0].mDataByteSize / (sizeof(float) * 2u);
        pushed = captureFrameRingPushInterleaved(
            capture->ring, input->mBuffers[0].mData, frames);
    }
    else if (input->mNumberBuffers >= 2)
    {
        const size_t left_frames = input->mBuffers[0].mDataByteSize / sizeof(float);
        const size_t right_frames = input->mBuffers[1].mDataByteSize / sizeof(float);
        const size_t frames = left_frames < right_frames ? left_frames : right_frames;
        pushed = captureFrameRingPushPlanar(
            capture->ring, input->mBuffers[0].mData, input->mBuffers[1].mData, frames);
    }
    if (!pushed)
        atomic_fetch_add_explicit(&capture->push_failures, 1, memory_order_relaxed);
    return noErr;
}
```

`coreAudioCaptureRestart` must stop/destroy the current IOProc when present,
re-resolve the device name, revalidate the format, and start a new IOProc.
`coreAudioCaptureClose` must stop/destroy without terminating the CoreAudio
process globally.

- [ ] **Step 4: Verify compiler and hardware probe**

Run: `integration/test/test-coreaudio-capture.sh`

Expected on the source Mac: `CoreAudio callbacks=` with a value at least 50.
Other CI machines print `BlackHole unavailable; hardware callback probe skipped`.

- [ ] **Step 5: Commit**

```bash
git add integration/capture/coreaudio_capture.* integration/test/coreaudio_capture_harness.c integration/test/test-coreaudio-capture.sh
git commit -m "feat: capture BlackHole through CoreAudio IOProc"
```

---

### Task 5: Replace the Blocking Capture Main Loop

**Files:**
- Modify: `integration/capture/capture-blackhole-pa.c`
- Modify: `integration/scripts/build-macos.sh`
- Modify: `integration/test/test-fifo-resilience.sh`
- Delete: `integration/capture/capture_watchdog.c`
- Delete: `integration/capture/capture_watchdog.h`
- Move tests:
  - `integration/test/watchdog_decision_harness.c` becomes
    `integration/test/capture_recovery_harness.c`
  - `integration/test/test-watchdog-recovery.sh` keeps its filename but compiles
    `capture_clock.c` and `capture_recovery_harness.c`

**Interfaces:**
- Consumes: ring, clock, recovery thresholds, and `CoreAudioCapture`.
- Produces: unchanged capture CLI and FIFO contract.

- [ ] **Step 1: Make the source contract fail**

Update `integration/test/test-fifo-resilience.sh` to assert:

```zsh
for token in 'captureClockNextBlock' 'coreAudioCaptureOpen' 'write_channel' \
  'open_fifo_writer' 'CAPTURE_WATCHDOG_RECOVER'; do
  grep -q "$token" "$capture_src" || exit 1
done
grep -q 'Pa_ReadStream' "$capture_src" && exit 1
grep -q '_exit(8)' "$capture_src" && exit 1
```

Run: `integration/test/test-fifo-resilience.sh`

Expected: fails because the current capture source still contains
`Pa_ReadStream`.

- [ ] **Step 2: Rewrite the capture main**

The new main follows this fixed cycle:

```c
captureFrameRingInit(&ring);
coreAudioCaptureOpen(&capture, requested_device, &ring);
start_recovery_thread(&recovery, &capture);

uint64_t next_deadline = monotonic_ns();
while (running)
{
    float block[CAPTURE_BLOCK_FRAMES * CAPTURE_CHANNELS];
    CaptureClockBlock selected = captureClockNextBlock(
        &ring, block, CAPTURE_BLOCK_FRAMES, CAPTURE_MAX_BACKLOG_FRAMES);

    if (!write_stereo_split(block, selected.frames, left_fd, right_fd))
        break;

    publish_metrics(block, selected, &capture);
    next_deadline += 10ULL * 1000000ULL;
    sleep_until_with_catchup(next_deadline, &next_deadline);
}

stop_recovery_thread(&recovery);
coreAudioCaptureClose(&capture);
```

Implement these helper contracts in the same file:

- `sleep_until_with_catchup`: sleeps to the next 10 ms deadline; if the writer
  is late by more than 200 ms, resets the deadline to now and counts one catchup.
- `write_stereo_split`: always passes the same `frames` to both
  `extractChannelS24In32` calls and both FIFO writes.
- `start_recovery_thread`: every 200 ms evaluates
  `capture_watchdog_decide(now, callback_ms)`;
  - `CAPTURE_WATCHDOG_NONE`: no action.
  - `CAPTURE_WATCHDOG_RECOVER`: if the recovery interval has elapsed, call
    `coreAudioCaptureRestart`.
  - `CAPTURE_WATCHDOG_EXIT_PROCESS`: log and exit non-zero.

Do not close the FIFO descriptors or reset the writer while recovery runs.

- [ ] **Step 3: Update the build without PortAudio**

In `integration/scripts/build-macos.sh`, compile:

```zsh
clang -O2 -Wall -Wextra -mmacosx-version-min="$deployment_target" \
  -I"$repo_root/integration/capture" \
  -o "$build_dir/bin/capture-blackhole" \
  "$repo_root/integration/capture/capture-blackhole-pa.c" \
  "$repo_root/integration/capture/capture_ring.c" \
  "$repo_root/integration/capture/capture_clock.c" \
  "$repo_root/integration/capture/coreaudio_capture.c" \
  "$repo_root/integration/capture/audio_metrics.c" \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework AudioUnit \
  -framework CoreServices \
  -framework CoreFoundation
```

Remove the PortAudio compatibility build from `build-macos.sh`; leave the
separate compatibility script for now so other branches can still consume it.

- [ ] **Step 4: Run targeted tests**

Run:

```sh
integration/test/test-capture-ring.sh
integration/test/test-coreaudio-capture.sh
integration/test/test-watchdog-recovery.sh
integration/test/test-fifo-resilience.sh
./integration/scripts/build-macos.sh
```

Expected: all exit 0. `strings .build/bin/capture-blackhole` must not contain
`Pa_ReadStream`.

- [ ] **Step 5: Commit**

```bash
git add integration/capture integration/test integration/scripts/build-macos.sh
git commit -m "fix: keep capture clock continuous while BlackHole is idle"
```

---

### Task 6: Publish Capture Health Counters

**Files:**
- Modify: `integration/capture/audio_metrics.h`
- Modify: `integration/capture/audio_metrics.c`
- Modify: `integration/capture/capture-blackhole-pa.c`
- Create: `integration/test/metrics_publish_harness.c`
- Modify: `integration/test/test-capture-ring.sh`
- Modify: `native/Sources/StereoPairCore/MetricsReader.swift`
- Modify: `native/Tests/StereoPairCoreTests/ChannelMetricsApplicationTests.swift`

**Interfaces:**
- Consumes: callback heartbeat/count, writer silence/drop counts.
- Produces: appended 64/32-bit counters in shared memory:
  - `callbackCount`
  - `generatedSilenceCycles`
  - `droppedFrames`
  - `recoveryAttempts`
  - `successfulRecoveries`

- [ ] **Step 1: Write the failing shared-memory test**

Create `integration/test/metrics_publish_harness.c` that:

1. Opens a uniquely named metrics publisher.
2. Publishes nonzero callback, silence, drop, and recovery counters.
3. Maps the shared memory and verifies the values.
4. Closes and removes the shared-memory object.

Use assertions with plain `if` and `fprintf`, matching the other C harnesses.
Compile it in `test-capture-ring.sh` with `audio_metrics.c` and link
`-lrt` only when the host is Linux; macOS uses libSystem.

Run `integration/test/test-capture-ring.sh`.

Expected: compilation fails because the counter fields and publish arguments
do not exist.

- [ ] **Step 2: Extend the metrics contract**

Append to `SnapcastAudioMetrics`:

```c
uint64_t callbackCount;
uint64_t generatedSilenceCycles;
uint64_t droppedFrames;
uint32_t recoveryAttempts;
uint32_t successfulRecoveries;
```

Define:

```c
typedef struct
{
    uint64_t callback_count;
    uint64_t generated_silence_cycles;
    uint64_t dropped_frames;
    uint32_t recovery_attempts;
    uint32_t successful_recoveries;
} SnapcastCaptureMetrics;
```

Change the publish signature to:

```c
void audioMetricsPublisherPublish(
    SnapcastAudioMetricsPublisher*,
    const SnapcastChannelMetrics* left,
    const SnapcastChannelMetrics* right,
    uint32_t sample_rate,
    const SnapcastCaptureMetrics* capture);
```

Copy counters inside the sequence-protected publication block.

- [ ] **Step 3: Update the Swift reader layout**

Append the same fields to `SharedAudioMetrics` in the same order and width.
Add the counters to `AudioMetricsSnapshot` with defaults so existing test
constructors continue to compile:

```swift
public var callbackCount: UInt64 = 0
public var generatedSilenceCycles: UInt64 = 0
public var droppedFrames: UInt64 = 0
public var recoveryAttempts: UInt32 = 0
public var successfulRecoveries: UInt32 = 0
```

Populate them when constructing the snapshot.

- [ ] **Step 4: Publish from the writer**

Maintain atomic counters in the capture main:

- increment silence cycles when `selected.has_audio == false`;
- add `selected.dropped_frames`;
- copy callback count and push-failure count from `CoreAudioCapture`;
- increment recovery counters around each restart.

Publish at most once per 20 ms; audio meter behavior does not need 100 Hz
shared-memory writes.

- [ ] **Step 5: Verify C and Swift tests**

Run:

```sh
integration/test/test-capture-ring.sh
swift test --package-path native
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add integration/capture/audio_metrics.* integration/capture/capture-blackhole-pa.c integration/test/metrics_publish_harness.c integration/test/test-capture-ring.sh native/Sources/StereoPairCore/MetricsReader.swift native/Tests/StereoPairCoreTests/ChannelMetricsApplicationTests.swift
git commit -m "feat: expose capture clock health metrics"
```

---

### Task 7: Update Documentation and Release Checks

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/troubleshooting.md`
- Modify: `docs/field-debugging-report.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `integration/test/test-native-release.sh`
- Modify: `integration/scripts/install-local.sh`

**Interfaces:**
- Consumes: completed capture behavior and tests.
- Produces: public operational guidance and complete release coverage.

- [ ] **Step 1: Add a failing documentation contract**

Add to `integration/test/test-native-release.sh` before executing tests:

```zsh
rg -q 'continuous 10 ms' "$repo_root/docs/architecture.md"
rg -q 'digital silence' "$repo_root/docs/troubleshooting.md"
```

Run: `integration/test/test-native-release.sh --automated-only`

Expected: exits non-zero because the new wording is absent.

- [ ] **Step 2: Update architecture and operations text**

Document:

- CoreAudio IOProc callback capture.
- Lock-free ring and continuous 10 ms writer.
- Digital silence throughout idle and recovery.
- Callback heartbeat health, 2 s recovery, and 15 s last-resort exit.
- No FIFO reconnect on ordinary idle.

Keep the existing acoustic and snapclient synchronization explanations.

- [ ] **Step 3: Update installation source copying**

Ensure `install-local.sh` installs every new capture source file referenced by
diagnostics, or copy the whole `integration/capture` source set with explicit
file names. Do not use broad globs that could pick up generated files.

- [ ] **Step 4: Run required checks**

Run the complete release command set from `AGENTS.md`, including:

```sh
./integration/scripts/build-macos.sh
swift test --package-path native
swift build --package-path native -c release
integration/test/test-capture-ring.sh
integration/test/test-coreaudio-capture.sh
integration/test/test-watchdog-recovery.sh
integration/test/test-fifo-resilience.sh
integration/test/test-native-release.sh --automated-only
./scripts/check-public-tree.sh
```

Expected: every command exits 0.

- [ ] **Step 5: Commit**

```bash
git add README.md AGENTS.md docs integration/test/test-native-release.sh integration/scripts/install-local.sh
git commit -m "docs: document continuous BlackHole capture clock"
```

---

### Task 8: Hardware Idle and Resume Acceptance

**Files:**
- Modify: `docs/hardware-acceptance.md`

**Interfaces:**
- Consumes: the built capture helper and live source/remote Mac pair.
- Produces: recorded evidence for the original symptom.

- [ ] **Step 1: Add the acceptance case**

Add a checklist item:

```markdown
- [ ] Leave BlackHole without a producer for at least 10 minutes, then resume
  playback. The splitter PID must not change, neither FIFO may reconnect, and
  playback must start without the prior initial stutter.
```

- [ ] **Step 2: Run the ten-minute live idle test**

Record the capture PID and callback count before idle, wait at least 10 minutes,
then resume audio. Verify:

- capture PID unchanged;
- no `Capture watchdog` or FIFO reconnect log;
- `LeftAudio` and `RightAudio` clients remain connected;
- local and remote logs contain no `Not enough frames`, `age > 0`,
  `onResync`, or underrun during resume;
- no audible startup stutter.

- [ ] **Step 3: Run one short recovery fault test**

Stop and restart the CoreAudio device path once without restarting the capture
process. Verify that digital silence continues during recovery, callback count
resumes, and both clients remain connected.

- [ ] **Step 4: Commit acceptance evidence**

Record non-sensitive environment details only:

```bash
git add docs/hardware-acceptance.md
git commit -m "test: document long-idle capture acceptance"
```

## Final Verification

After all tasks:

1. Run every command in the repository's Required Checks section.
2. Confirm `.build/bin/capture-blackhole` has no `Pa_ReadStream` symbol.
3. Confirm `launchctl` reports one stable splitter PID through the idle test.
4. Review `git diff main...HEAD` for unrelated changes.
5. Do not claim the original stutter is fixed without the ten-minute live
   idle/resume evidence.
