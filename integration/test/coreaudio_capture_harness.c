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
    const size_t available = captureFrameRingAvailable(&ring);
    const unsigned long long push_failures =
        atomic_load_explicit(&capture.push_failures, memory_order_acquire);
    coreAudioCaptureClose(&capture);
    if (callbacks < 50)
    {
        fprintf(stderr, "expected continuous callbacks, got %llu\n", callbacks);
        return 1;
    }
    if (available == 0)
    {
        fprintf(stderr, "callbacks did not produce usable frames (push failures=%llu)\n", push_failures);
        return 1;
    }
    printf("CoreAudio callbacks=%llu frames=%zu\n", callbacks, available);
    return 0;
}
