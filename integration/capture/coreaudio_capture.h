#pragma once

#include "capture_ring.h"

#include <CoreAudio/CoreAudio.h>

#include <stdatomic.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef struct
{
    AudioObjectID device_id;
    AudioDeviceIOProcID proc_id;
    CaptureFrameRing* ring;
    atomic_llong callback_ms;
    atomic_ullong callback_count;
    atomic_ullong push_failures;
    bool started;
    char requested_name[128];
} CoreAudioCapture;

int coreAudioCaptureOpen(CoreAudioCapture* capture, const char* requested_name, CaptureFrameRing* ring);
int coreAudioCaptureRestart(CoreAudioCapture* capture);
void coreAudioCaptureClose(CoreAudioCapture* capture);

#ifdef __cplusplus
}
#endif
