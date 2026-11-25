#include "capture_ring.h"

#include <string.h>

#define CAPTURE_RING_MASK (CAPTURE_RING_FRAMES - 1u)

_Static_assert((CAPTURE_RING_FRAMES & CAPTURE_RING_MASK) == 0, "capture ring size must be a power of two");

void captureFrameRingInit(CaptureFrameRing* ring)
{
    if (ring == NULL)
        return;
    memset(ring, 0, sizeof(*ring));
    atomic_init(&ring->write_frame, 0);
    atomic_init(&ring->read_frame, 0);
}

size_t captureFrameRingAvailable(const CaptureFrameRing* ring)
{
    if (ring == NULL)
        return 0;
    const uint64_t write = atomic_load_explicit(&ring->write_frame, memory_order_acquire);
    const uint64_t read = atomic_load_explicit(&ring->read_frame, memory_order_relaxed);
    return (size_t)(write - read);
}

bool captureFrameRingPushInterleaved(CaptureFrameRing* ring, const float* stereo, size_t frames)
{
    if ((ring == NULL) || (stereo == NULL) || frames == 0)
        return false;

    const uint64_t write = atomic_load_explicit(&ring->write_frame, memory_order_relaxed);
    const uint64_t read = atomic_load_explicit(&ring->read_frame, memory_order_acquire);
    if (frames > CAPTURE_RING_FRAMES - (size_t)(write - read))
        return false;

    for (size_t i = 0; i < frames; ++i)
    {
        const size_t position = (size_t)((write + i) & CAPTURE_RING_MASK);
        ring->left[position] = stereo[i * CAPTURE_CHANNELS];
        ring->right[position] = stereo[i * CAPTURE_CHANNELS + 1u];
    }
    atomic_store_explicit(&ring->write_frame, write + frames, memory_order_release);
    return true;
}

bool captureFrameRingPushPlanar(CaptureFrameRing* ring, const float* left, const float* right, size_t frames)
{
    if ((ring == NULL) || (left == NULL) || (right == NULL) || frames == 0)
        return false;

    const uint64_t write = atomic_load_explicit(&ring->write_frame, memory_order_relaxed);
    const uint64_t read = atomic_load_explicit(&ring->read_frame, memory_order_acquire);
    if (frames > CAPTURE_RING_FRAMES - (size_t)(write - read))
        return false;

    for (size_t i = 0; i < frames; ++i)
    {
        const size_t position = (size_t)((write + i) & CAPTURE_RING_MASK);
        ring->left[position] = left[i];
        ring->right[position] = right[i];
    }
    atomic_store_explicit(&ring->write_frame, write + frames, memory_order_release);
    return true;
}

size_t captureFrameRingPop(CaptureFrameRing* ring, float* stereo, size_t frames)
{
    if ((ring == NULL) || (stereo == NULL) || frames == 0)
        return 0;

    const uint64_t read = atomic_load_explicit(&ring->read_frame, memory_order_relaxed);
    const uint64_t write = atomic_load_explicit(&ring->write_frame, memory_order_acquire);
    const size_t available = (size_t)(write - read);
    const size_t count = frames < available ? frames : available;
    for (size_t i = 0; i < count; ++i)
    {
        const size_t position = (size_t)((read + i) & CAPTURE_RING_MASK);
        stereo[i * CAPTURE_CHANNELS] = ring->left[position];
        stereo[i * CAPTURE_CHANNELS + 1u] = ring->right[position];
    }
    atomic_store_explicit(&ring->read_frame, read + count, memory_order_release);
    return count;
}

size_t captureFrameRingDiscard(CaptureFrameRing* ring, size_t frames)
{
    if ((ring == NULL) || frames == 0)
        return 0;

    const uint64_t read = atomic_load_explicit(&ring->read_frame, memory_order_relaxed);
    const uint64_t write = atomic_load_explicit(&ring->write_frame, memory_order_acquire);
    const size_t available = (size_t)(write - read);
    const size_t count = frames < available ? frames : available;
    atomic_store_explicit(&ring->read_frame, read + count, memory_order_release);
    return count;
}
