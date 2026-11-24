#pragma once

#include <portaudio.h>

#include <pthread.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef enum
{
    CAPTURE_WATCHDOG_NONE = 0,
    CAPTURE_WATCHDOG_ABORT,
    CAPTURE_WATCHDOG_EXIT_PROCESS
} CaptureWatchdogDecision;

typedef struct
{
    pthread_mutex_t mutex;
    PaStream* stream;
} CaptureStreamHandle;

CaptureWatchdogDecision capture_watchdog_decide(long long now_ms, long long last_read_ms);

bool capture_stream_init(CaptureStreamHandle* handle);
void capture_stream_destroy(CaptureStreamHandle* handle);
void capture_stream_replace(CaptureStreamHandle* handle, PaStream* stream);
PaStream* capture_stream_take(CaptureStreamHandle* handle);
bool capture_stream_abort(CaptureStreamHandle* handle);

#ifdef __cplusplus
}
#endif
