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
