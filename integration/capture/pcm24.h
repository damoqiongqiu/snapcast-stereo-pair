#pragma once

#include <stddef.h>
#include <stdint.h>

#include <math.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef enum
{
    AUDIO_CHANNEL_LEFT = 0,
    AUDIO_CHANNEL_RIGHT = 1
} AudioChannel;

static inline int32_t floatToS24(float sample)
{
    float scaled = sample * 8388608.0F;
    if (scaled != scaled)
        return 0;
    if (scaled >= 8388607.0F)
        return 8388607;
    if (scaled <= -8388608.0F)
        return -8388608;
    return (int32_t)lrintf(scaled);
}

static inline void floatToS24In32(const float* input, int32_t* output, size_t sample_count)
{
    for (size_t i = 0; i < sample_count; ++i)
        output[i] = floatToS24(input[i]);
}

static inline void extractChannelS24In32(const float* stereo, int32_t* channel, size_t frames, AudioChannel side)
{
    const size_t offset = side == AUDIO_CHANNEL_LEFT ? 0 : 1;
    for (size_t i = 0; i < frames; ++i)
        channel[i] = floatToS24(stereo[i * 2 + offset]);
}

#ifdef __cplusplus
}
#endif
