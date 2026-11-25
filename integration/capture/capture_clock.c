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
