#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    float peakDb;
    float rmsDb;
    uint32_t clipped;
} SnapcastChannelMetrics;

typedef struct
{
    uint64_t sequence;
    uint64_t timestampNs;
    float leftPeakDb;
    float leftRmsDb;
    float rightPeakDb;
    float rightRmsDb;
    uint32_t leftClipped;
    uint32_t rightClipped;
    uint32_t sampleRate;
    uint32_t flags;
    uint64_t callbackCount;
    uint64_t generatedSilenceCycles;
    uint64_t droppedFrames;
    uint32_t recoveryAttempts;
    uint32_t successfulRecoveries;
} SnapcastAudioMetrics;

typedef struct
{
    uint64_t callback_count;
    uint64_t generated_silence_cycles;
    uint64_t dropped_frames;
    uint32_t recovery_attempts;
    uint32_t successful_recoveries;
} SnapcastCaptureMetrics;

typedef struct
{
    int fd;
    SnapcastAudioMetrics* metrics;
    char name[96];
} SnapcastAudioMetricsPublisher;

void audioMetricsDefaultName(char* output, size_t capacity);
void audioMetricsCalculateChannel(
    const float* interleaved, size_t frames, size_t channel, size_t channels, SnapcastChannelMetrics* metrics);
bool audioMetricsPublisherOpen(SnapcastAudioMetricsPublisher* publisher, const char* name);
void audioMetricsPublisherPublish(
    SnapcastAudioMetricsPublisher* publisher,
    const SnapcastChannelMetrics* left,
    const SnapcastChannelMetrics* right,
    uint32_t sampleRate,
    const SnapcastCaptureMetrics* capture);
void audioMetricsPublisherClose(SnapcastAudioMetricsPublisher* publisher);

#ifdef __cplusplus
}
#endif
