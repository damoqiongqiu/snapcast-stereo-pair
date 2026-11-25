# BlackHole Capture Clock Design

## Status

Proposed for implementation.

## Problem

The source runtime currently captures BlackHole through a blocking
`Pa_ReadStream` call. When BlackHole stops delivering frames during an
extended idle period, the capture process treats the absence of data as a
device failure. The watchdog aborts the stream and eventually exits for
launchd to relaunch it.

That recovery path closes and reconnects the left and right FIFOs. Snapserver
then resets the logical stream timeline, and both Snapclients must rebuild
their buffers before playback becomes stable again. The audible result is a
stutter when audio resumes after a long idle period.

The root cause is the capture boundary: it conflates "BlackHole currently has
no audio to deliver" with "the CoreAudio device is no longer running."
Increasing buffers or watchdog timeouts only changes the symptom.

## Goals

- Keep the Snapserver input timeline continuous while BlackHole is idle.
- Preserve the existing 48 kHz, stereo float32 capture to dual mono
  `S24In32` FIFO format.
- Recover from a genuinely stalled CoreAudio callback path without using a
  routine process restart.
- Continue sending digital silence to Snapserver while a device fault is
  being recovered.
- Keep all file I/O, allocation, logging, metrics calculation, and blocking
  operations out of the real-time CoreAudio callback.
- Preserve a shared sample clock and block boundary for left and right.

## Non-Goals

- Changing Snapserver's 20 ms chunks or 200 ms default client buffer.
- Changing volume handling, routing, physical placement, or snapclient
  synchronization algorithms.
- Adding resampling or lossy codecs.
- Automatically modifying the user's live services during development.

## Architecture

The capture helper becomes a CoreAudio HAL callback producer with an
independent FIFO clock bridge:

```text
BlackHole 2ch
    |
    | CoreAudio IOProc callback
    v
lock-free stereo block ring
    |
    | latest complete 10 ms blocks
    v
48 kHz writing clock
    |---- real frames when available
    |---- zero-valued frames when idle or recovering
    v
left.pcm / right.pcm FIFOs
    |
    v
Snapserver LeftAudio / RightAudio
```

The writer is the stable clock observed by Snapserver. CoreAudio callbacks are
the source of real samples, but a temporary absence of callbacks no longer
stops the FIFO stream or causes client resynchronization.

## Components

### CoreAudio Capture

- Resolve `BlackHole 2ch` by CoreAudio device name, preserving
  `CAPTURE_DEVICE` as an override.
- Validate 48 kHz stereo float32 input support.
- Install one HAL IOProc and start the device.
- Copy each complete input block into a bounded single-producer,
  single-consumer ring buffer.
- Update callback heartbeat and dropped-block counters atomically.

The callback must not write to the FIFO, allocate memory, log, or take a
blocking lock.

### FIFO Clock Writer

- Emit exactly 480 frames every 10 ms using monotonic pacing.
- Write the same left and right frame count on every cycle.
- If one or more complete captured blocks are available, convert the newest
  safe block to `S24In32` and write it.
- If no complete block is available, write zero-valued left and right PCM.
- If the available block is older than 50 ms, discard it and keep writing
  silence until fresh input arrives.
- Never block the CoreAudio callback on a slow FIFO reader. Existing FIFO
  reopen behavior remains on the writer thread.

The first fresh block after idle may be discarded to avoid late playback.
Digital silence remains continuous across that boundary.

### Metrics

A worker thread publishes channel metrics and operational counters through the
existing shared-memory metrics format. New counters make the distinction
observable:

- CoreAudio callback count.
- Callback heartbeat age.
- Generated-silence cycles.
- Stale or dropped input blocks.
- Device recovery attempts.
- Successful recovery count.

### Device Lifecycle

The capture helper uses explicit states:

```text
starting -> running -> degraded -> recovering -> running
                         |
                         +---- after bounded failures -> process exit
```

- `running`: callbacks are arriving within the expected cadence.
- `degraded`: no callback heartbeat for 2 seconds; the writer continues
  producing silence.
- `recovering`: stop, destroy, recreate, and start the IOProc using bounded
  retries with a short backoff.
- A recovery attempt that hangs in CoreAudio runs outside the writer and
  callback paths.
- Process exit is a last resort after repeated recovery failure, not the
  primary idle transition.

The FIFO writer remains active while recovery runs. A process exit is
acceptable only when the CoreAudio HAL itself cannot be recovered safely.

## Error Handling

- Missing or unsupported BlackHole device: report a clear startup error and
  exit non-zero.
- FIFO reader unavailable: retain the existing non-blocking reopen loop.
- FIFO write failure: reopen only the affected FIFO and continue.
- Callback overflow or malformed block: discard that block, count it, and
  continue with silence or the next complete block.
- Lost device or sample-rate change: enter recovery and rebuild the IOProc.
- Device callback stalls: enter degraded mode without stopping FIFO output.

## Testing

### Unit and Contract Tests

- Ring buffer accepts complete stereo blocks and returns frames in order.
- Full ring rejects or drops the oldest block without blocking the producer.
- Writer emits one exact 10 ms block per cycle.
- Writer emits silence when the ring is empty.
- Writer switches from silence to the first fresh real block.
- Writer discards stale blocks after a long idle period.
- Left and right output lengths remain identical for every writer cycle.
- Recovery state reaches `degraded` only after the configured heartbeat
  timeout.
- Recovery success returns to `running`; repeated failure reaches the bounded
  process-exit condition.

The tests use synthetic frames and monotonic time inputs; they do not require a
physical audio device.

### Hardware Acceptance

Run on the source Mac with the real BlackHole device:

1. Start the pair and confirm both streams are connected.
2. Produce no BlackHole output for at least 10 minutes.
3. Confirm the capture PID does not restart and FIFO output continues.
4. Resume audio and confirm playback begins without the previous initial
   stutter.
5. Confirm neither client logs buffer underruns or stream resync events.
6. Repeat once after sleep/wake and once after changing output devices.

Record macOS, CPU architecture, BlackHole version, and heard result in the
hardware acceptance notes.

## Migration

- Replace the PortAudio blocking-read path with the CoreAudio HAL backend.
- Keep the command-line interface and FIFO path contract unchanged.
- Keep the existing FIFO resilience behavior.
- Remove the runtime dependency on PortAudio only after the direct HAL backend
  passes build, unit, and hardware acceptance checks.
- Update architecture and troubleshooting documentation to describe
  callback-heartbeat health and continuous silence output.

## Acceptance Criteria

- A long idle period no longer causes splitter relaunches.
- No FIFO disconnect or Snapserver stream timeline reset occurs merely because
  BlackHole produced no audio.
- Audio resumes without the reproducible initial stutter.
- A simulated stalled callback heartbeat triggers one controlled recovery
  rather than repeated watchdog exits.
- Existing left/right channel identity and 48 kHz/24-bit format remain intact.
- Required repository checks pass.
