#include "capture_watchdog.h"

#include <stddef.h>

CaptureWatchdogDecision capture_watchdog_decide(long long now_ms, long long last_read_ms)
{
    if (last_read_ms <= 0 || now_ms - last_read_ms <= 1000)
        return CAPTURE_WATCHDOG_NONE;
    if (now_ms - last_read_ms > 3000)
        return CAPTURE_WATCHDOG_EXIT_PROCESS;
    return CAPTURE_WATCHDOG_ABORT;
}

bool capture_stream_init(CaptureStreamHandle* handle)
{
    handle->stream = NULL;
    return pthread_mutex_init(&handle->mutex, NULL) == 0;
}

void capture_stream_destroy(CaptureStreamHandle* handle)
{
    pthread_mutex_destroy(&handle->mutex);
}

void capture_stream_replace(CaptureStreamHandle* handle, PaStream* stream)
{
    pthread_mutex_lock(&handle->mutex);
    handle->stream = stream;
    pthread_mutex_unlock(&handle->mutex);
}

PaStream* capture_stream_take(CaptureStreamHandle* handle)
{
    pthread_mutex_lock(&handle->mutex);
    PaStream* stream = handle->stream;
    handle->stream = NULL;
    pthread_mutex_unlock(&handle->mutex);
    return stream;
}

bool capture_stream_abort(CaptureStreamHandle* handle)
{
    pthread_mutex_lock(&handle->mutex);
    PaStream* stream = handle->stream;
    bool aborted = stream != NULL && Pa_AbortStream(stream) == paNoError;
    pthread_mutex_unlock(&handle->mutex);
    return aborted;
}
