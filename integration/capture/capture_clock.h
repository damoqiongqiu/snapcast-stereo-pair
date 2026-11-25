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

typedef struct
{
    bool has_audio;
    size_t frames;
    size_t dropped_frames;
} CaptureClockBlock;

CaptureClockBlock captureClockNextBlock(
    CaptureFrameRing* ring, float* output, size_t frames, size_t max_backlog_frames);

#ifdef __cplusplus
}
#endif
