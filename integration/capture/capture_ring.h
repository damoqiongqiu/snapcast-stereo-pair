#pragma once

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

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
