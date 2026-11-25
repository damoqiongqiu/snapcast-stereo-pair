#include "capture_clock.h"

CaptureClockBlock captureClockNextBlock(
    CaptureFrameRing* ring, float* output, size_t frames, size_t max_backlog_frames)
{
    CaptureClockBlock result = {.has_audio = false, .frames = frames, .dropped_frames = 0};
    if ((ring == NULL) || (output == NULL) || (frames == 0))
        return result;

    const size_t available = captureFrameRingAvailable(ring);
    if (available > max_backlog_frames && available > frames)
        result.dropped_frames = captureFrameRingDiscard(ring, available - frames);

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
