#include "audio_metrics.h"

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static const float kSilenceDb = -120.0F;

static float amplitude_to_db(float amplitude)
{
    if (amplitude <= 0.0F)
        return kSilenceDb;
    float db = 20.0F * log10f(amplitude);
    return db < kSilenceDb ? kSilenceDb : db;
}

void audioMetricsDefaultName(char* output, size_t capacity)
{
    snprintf(output, capacity, "/snapcast-stereo-metrics-%u", (unsigned)getuid());
}

void audioMetricsCalculateChannel(
    const float* interleaved, size_t frames, size_t channel, size_t channels, SnapcastChannelMetrics* metrics)
{
    memset(metrics, 0, sizeof(*metrics));
    if ((interleaved == NULL) || (channels == 0) || (channel >= channels) || (frames == 0))
    {
        metrics->peakDb = kSilenceDb;
        metrics->rmsDb = kSilenceDb;
        return;
    }

    float peak = 0.0F;
    double sumSquares = 0.0;
    for (size_t frame = 0; frame < frames; ++frame)
    {
        float sample = fabsf(interleaved[(frame * channels) + channel]);
        if (sample > 1.0F)
        {
            metrics->clipped = 1;
            sample = 1.0F;
        }
        if (sample > peak)
            peak = sample;
        sumSquares += (double)sample * (double)sample;
    }

    metrics->peakDb = amplitude_to_db(peak);
    metrics->rmsDb = amplitude_to_db((float)sqrt(sumSquares / (double)frames));
}

static bool audioMetricsPublisherOpenOnce(SnapcastAudioMetricsPublisher* publisher)
{
    publisher->fd = shm_open(publisher->name, O_CREAT | O_RDWR, 0600);
    if (publisher->fd < 0)
        return false;
    if (ftruncate(publisher->fd, (off_t)sizeof(SnapcastAudioMetrics)) != 0)
        goto error;
    publisher->metrics = mmap(NULL, sizeof(SnapcastAudioMetrics), PROT_READ | PROT_WRITE, MAP_SHARED, publisher->fd, 0);
    if (publisher->metrics == MAP_FAILED)
    {
        publisher->metrics = NULL;
        goto error;
    }
    memset(publisher->metrics, 0, sizeof(*publisher->metrics));
    return true;

error:
    close(publisher->fd);
    publisher->fd = -1;
    return false;
}

bool audioMetricsPublisherOpen(SnapcastAudioMetricsPublisher* publisher, const char* name)
{
    memset(publisher, 0, sizeof(*publisher));
    publisher->fd = -1;
    if ((name == NULL) || (*name == '\0'))
        audioMetricsDefaultName(publisher->name, sizeof(publisher->name));
    else
        snprintf(publisher->name, sizeof(publisher->name), "%s%s", name[0] == '/' ? "" : "/", name);

    if (audioMetricsPublisherOpenOnce(publisher))
        return true;
    shm_unlink(publisher->name);
    return audioMetricsPublisherOpenOnce(publisher);
}

void audioMetricsPublisherPublish(
    SnapcastAudioMetricsPublisher* publisher,
    const SnapcastChannelMetrics* left,
    const SnapcastChannelMetrics* right,
    uint32_t sampleRate)
{
    if ((publisher == NULL) || (publisher->metrics == NULL))
        return;

    SnapcastAudioMetrics* metrics = publisher->metrics;
    atomic_fetch_add_explicit((_Atomic uint64_t*)&metrics->sequence, 1, memory_order_acq_rel);

    struct timespec now = {0};
    clock_gettime(CLOCK_MONOTONIC, &now);
    metrics->timestampNs = ((uint64_t)now.tv_sec * 1000000000ULL) + (uint64_t)now.tv_nsec;
    metrics->leftPeakDb = left->peakDb;
    metrics->leftRmsDb = left->rmsDb;
    metrics->rightPeakDb = right->peakDb;
    metrics->rightRmsDb = right->rmsDb;
    metrics->leftClipped = left->clipped;
    metrics->rightClipped = right->clipped;
    metrics->sampleRate = sampleRate;
    metrics->flags = 1;

    atomic_fetch_add_explicit((_Atomic uint64_t*)&metrics->sequence, 1, memory_order_release);
}

void audioMetricsPublisherClose(SnapcastAudioMetricsPublisher* publisher)
{
    if ((publisher == NULL) || (publisher->metrics == NULL))
        return;
    publisher->metrics->flags = 0;
    munmap(publisher->metrics, sizeof(SnapcastAudioMetrics));
    publisher->metrics = NULL;
    close(publisher->fd);
    publisher->fd = -1;
    shm_unlink(publisher->name);
}
