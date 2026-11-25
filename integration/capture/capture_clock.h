#pragma once

#include "capture_ring.h"

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define CAPTURE_BLOCK_FRAMES 480u
#define CAPTURE_MAX_BACKLOG_FRAMES 2400u
#define CAPTURE_CALLBACK_TIMEOUT_MS 2000
#define CAPTURE_RECOVERY_INTERVAL_MS 2000
#define CAPTURE_EXIT_TIMEOUT_MS 15000

typedef enum
{
    CAPTURE_WATCHDOG_NONE = 0,
    CAPTURE_WATCHDOG_RECOVER,
    CAPTURE_WATCHDOG_EXIT_PROCESS
} CaptureWatchdogDecision;

typedef struct
{
    bool has_audio;
    size_t frames;
    size_t dropped_frames;
} CaptureClockBlock;

CaptureClockBlock captureClockNextBlock(
    CaptureFrameRing* ring, float* output, size_t frames, size_t max_backlog_frames);
CaptureWatchdogDecision capture_watchdog_decide(long long now_ms, long long last_callback_ms);
bool capture_watchdog_should_attempt_recovery(long long now_ms, long long last_attempt_ms);

#ifdef __cplusplus
}
#endif
