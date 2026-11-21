#pragma once

#include <atomic>
#include <cstdint>

namespace player
{

inline bool coreAudioQueueNeedsRestart(
    std::int32_t status, bool timelineDiscontinuity, bool queueStarted)
{
    return timelineDiscontinuity || (queueStarted && (status != 0));
}

class CoreAudioCallbackState
{
public:
    bool callbackSuppressed() const noexcept
    {
        return restartRequested_.load(std::memory_order_acquire);
    }

    bool requestRestart() noexcept
    {
        return !restartRequested_.exchange(true, std::memory_order_acq_rel);
    }

    void reset() noexcept
    {
        restartRequested_.store(false, std::memory_order_release);
    }

private:
    std::atomic<bool> restartRequested_{false};
};

} // namespace player
