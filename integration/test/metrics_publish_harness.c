#include "audio_metrics.h"

#include <fcntl.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void)
{
    char storage_name[96];
    snprintf(storage_name, sizeof(storage_name), "snapcast-metrics-test-%u", (unsigned)getpid());

    SnapcastAudioMetricsPublisher publisher;
    if (!audioMetricsPublisherOpen(&publisher, storage_name))
    {
        fprintf(stderr, "could not open metrics publisher\n");
        return 1;
    }

    const SnapcastChannelMetrics left = {.peakDb = -3.0F, .rmsDb = -12.0F, .clipped = 0};
    const SnapcastChannelMetrics right = {.peakDb = -6.0F, .rmsDb = -15.0F, .clipped = 1};
    const SnapcastCaptureMetrics capture = {
        .callback_count = 1200,
        .generated_silence_cycles = 34,
        .dropped_frames = 960,
        .recovery_attempts = 2,
        .successful_recoveries = 1,
    };
    audioMetricsPublisherPublish(&publisher, &left, &right, 48000, &capture);

    const int fd = shm_open(publisher.name, O_RDONLY, 0);
    if (fd < 0)
    {
        audioMetricsPublisherClose(&publisher);
        return 2;
    }
    const SnapcastAudioMetrics* metrics = mmap(
        NULL, sizeof(SnapcastAudioMetrics), PROT_READ, MAP_SHARED, fd, 0);
    close(fd);
    if (metrics == MAP_FAILED)
    {
        audioMetricsPublisherClose(&publisher);
        return 3;
    }

    int failures = 0;
    if (metrics->callbackCount != capture.callback_count)
    {
        fprintf(stderr, "callback count mismatch\n");
        ++failures;
    }
    if (metrics->generatedSilenceCycles != capture.generated_silence_cycles)
    {
        fprintf(stderr, "silence cycle mismatch\n");
        ++failures;
    }
    if (metrics->droppedFrames != capture.dropped_frames)
    {
        fprintf(stderr, "dropped frame mismatch\n");
        ++failures;
    }
    if ((metrics->recoveryAttempts != capture.recovery_attempts) ||
        (metrics->successfulRecoveries != capture.successful_recoveries))
    {
        fprintf(stderr, "recovery counter mismatch\n");
        ++failures;
    }

    munmap((void*)metrics, sizeof(SnapcastAudioMetrics));
    audioMetricsPublisherClose(&publisher);
    return failures == 0 ? 0 : 4;
}
