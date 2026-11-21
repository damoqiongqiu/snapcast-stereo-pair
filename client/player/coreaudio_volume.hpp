#pragma once

namespace player
{

inline float coreAudioQueueVolume(double volume, bool muted)
{
    if (muted || volume <= 0)
        return 0.0F;
    if (volume >= 1.0)
        return 1.0F;
    return static_cast<float>(volume);
}

} // namespace player
