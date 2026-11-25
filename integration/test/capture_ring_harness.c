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
