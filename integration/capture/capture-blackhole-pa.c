#include <portaudio.h>

#include "audio_metrics.h"
#include "capture_watchdog.h"
#include "fifo_io.h"
#include "pcm24.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile sig_atomic_t running = 1;

typedef struct
{
    const char* left_fifo;
    const char* right_fifo;
    const char* metrics_shm;
} CaptureOutputs;

static void stop_capture(int signal_number)
{
    (void)signal_number;
    running = 0;
}

/*
 * BlackHole stops delivering input frames once its producer goes away, which
 * leaves the blocking Pa_ReadStream below stuck forever with no error and no
 * data. The watchdog notices the stall and aborts the stream so the main loop
 * can reopen it (which restarts the CoreAudio device); if aborting cannot
 * unblock the read, give up and let launchd relaunch the process fresh.
 */
static atomic_llong g_last_read_ms = 0;
static CaptureStreamHandle g_stream_handle;
static bool g_stream_handle_initialized = false;

static long long monotonic_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void* capture_watchdog(void* argument)
{
    (void)argument;
    long long aborted_for_last_read = -1;
    while (running)
    {
        Pa_Sleep(1000);
        long long last = atomic_load(&g_last_read_ms);
        long long now = monotonic_ms();
        CaptureWatchdogDecision decision = capture_watchdog_decide(now, last);
        if (decision == CAPTURE_WATCHDOG_EXIT_PROCESS)
        {
            fprintf(stderr, "Capture watchdog: no input frames for %lld ms, exiting for relaunch\n", now - last);
            _exit(8);
        }
        if (decision == CAPTURE_WATCHDOG_ABORT && aborted_for_last_read != last)
        {
            fprintf(stderr, "Capture watchdog: no input frames for %lld ms, aborting stream\n", now - last);
            capture_stream_abort(&g_stream_handle);
            aborted_for_last_read = last;
        }
    }
    return NULL;
}

/*
 * The snapserver briefly closes its FIFO read ends across restarts and reader
 * cycles, which would turn any blocking writer into an instant EPIPE. Open the
 * FIFOs non-blocking and wait for a reader to appear instead of hanging on a
 * blocking open that may never be answered.
 */
static int open_fifo_writer(const char* path)
{
    for (;;)
    {
        int fd = open(path, O_WRONLY | O_NONBLOCK);
        if (fd >= 0)
            return fd;
        if ((errno == ENXIO || errno == ENOENT) && running)
        {
            Pa_Sleep(200);
            continue;
        }
        return -1;
    }
}

/*
 * Write a full buffer, transparently recovering when the server closes its
 * read end: close our side, wait for the reader to come back, reopen, retry.
 */
static bool write_channel(int* fd, const char* fifo_path, const void* data, size_t bytes)
{
    for (;;)
    {
        if (*fd < 0)
        {
            *fd = open_fifo_writer(fifo_path);
            if (*fd < 0)
                return false;
        }
        if (writeFully(*fd, data, bytes))
            return true;
        fprintf(stderr, "FIFO reader closed (%s), reopening\n", fifo_path);
        close(*fd);
        *fd = -1;
        if (!running)
            return false;
        Pa_Sleep(100);
    }
}

static int parse_outputs(int argc, char** argv, CaptureOutputs* outputs)
{
    outputs->left_fifo = NULL;
    outputs->right_fifo = NULL;
    outputs->metrics_shm = NULL;

    for (int i = 1; i < argc; ++i)
    {
        if ((strcmp(argv[i], "--left-fifo") == 0) && (i + 1 < argc))
            outputs->left_fifo = argv[++i];
        else if ((strcmp(argv[i], "--right-fifo") == 0) && (i + 1 < argc))
            outputs->right_fifo = argv[++i];
        else if ((strcmp(argv[i], "--metrics-shm") == 0) && (i + 1 < argc))
            outputs->metrics_shm = argv[++i];
        else
            return -1;
    }

    if ((outputs->left_fifo == NULL) != (outputs->right_fifo == NULL))
        return -1;
    return 0;
}

static int find_blackhole_input(void)
{
    const char* requested = getenv("CAPTURE_DEVICE");
    if (requested == NULL || *requested == '\0')
        requested = "BlackHole 2ch";

    const int device_count = Pa_GetDeviceCount();
    for (int i = 0; i < device_count; ++i)
    {
        const PaDeviceInfo* info = Pa_GetDeviceInfo(i);
        if (info != NULL && info->maxInputChannels >= 2 && strstr(info->name, requested) != NULL)
            return i;
    }
    return paNoDevice;
}

int main(int argc, char** argv)
{
    CaptureOutputs outputs;
    if (parse_outputs(argc, argv, &outputs) != 0)
    {
        fprintf(stderr, "Usage: %s [--left-fifo PATH --right-fifo PATH]\n", argv[0]);
        return 2;
    }

    signal(SIGINT, stop_capture);
    signal(SIGTERM, stop_capture);
    signal(SIGPIPE, SIG_IGN);
    setvbuf(stdout, NULL, _IONBF, 0);

    int left_fd = -1;
    int right_fd = -1;
    if (outputs.left_fifo != NULL)
    {
        left_fd = open_fifo_writer(outputs.left_fifo);
        right_fd = (left_fd >= 0) ? open_fifo_writer(outputs.right_fifo) : -1;
        if ((left_fd < 0) || (right_fd < 0))
        {
            fprintf(stderr, "Could not open capture FIFOs\n");
            if (left_fd >= 0)
                close(left_fd);
            if (right_fd >= 0)
                close(right_fd);
            return 3;
        }
    }

    PaError error = Pa_Initialize();
    if (error != paNoError)
    {
        fprintf(stderr, "PortAudio init failed: %s\n", Pa_GetErrorText(error));
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 1;
    }

    const int device = find_blackhole_input();
    if (device == paNoDevice)
    {
        fprintf(stderr, "BlackHole input device not found\n");
        Pa_Terminate();
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 2;
    }

    const PaDeviceInfo* info = Pa_GetDeviceInfo(device);
    const unsigned long frames_per_buffer = 480;
    PaStreamParameters input_parameters;
    memset(&input_parameters, 0, sizeof(input_parameters));
    input_parameters.device = device;
    input_parameters.channelCount = 2;
    input_parameters.sampleFormat = paFloat32;
    input_parameters.suggestedLatency = info->defaultLowInputLatency;
    input_parameters.hostApiSpecificStreamInfo = NULL;

    PaStream* stream = NULL;
    error = Pa_OpenStream(&stream, &input_parameters, NULL, 48000, frames_per_buffer, paClipOff, NULL, NULL);
    if (error != paNoError)
    {
        fprintf(stderr, "Could not open %s: %s\n", info->name, Pa_GetErrorText(error));
        Pa_Terminate();
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 3;
    }

    error = Pa_StartStream(stream);
    if (error != paNoError)
    {
        fprintf(stderr, "Could not start stream: %s\n", Pa_GetErrorText(error));
        Pa_CloseStream(stream);
        Pa_Terminate();
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 4;
    }
    if (!capture_stream_init(&g_stream_handle))
    {
        fprintf(stderr, "Could not initialize capture stream synchronization\n");
        Pa_StopStream(stream);
        Pa_CloseStream(stream);
        Pa_Terminate();
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 5;
    }
    g_stream_handle_initialized = true;
    capture_stream_replace(&g_stream_handle, stream);

    if (left_fd >= 0)
        fprintf(stderr, "Capturing %s at 48000 Hz into left/right 24-bit PCM FIFOs, 10 ms buffers\n", info->name);
    else
        fprintf(stderr, "Capturing %s at 48000 Hz, stereo float32 -> 24-bit PCM, 10 ms buffers\n", info->name);

    float buffer[480 * 2];
    int32_t pcm24[480 * 2];
    int32_t left[480];
    int32_t right[480];
    const bool use_fifos = (outputs.left_fifo != NULL);
    int exit_code = 0;
    pthread_t watchdog_thread;
    bool watchdog_started = false;
    SnapcastAudioMetricsPublisher metricsPublisher = {.fd = -1, .metrics = NULL};
    if (!audioMetricsPublisherOpen(&metricsPublisher, outputs.metrics_shm))
    {
        fprintf(stderr, "Could not open shared audio metrics: %s\n", strerror(errno));
        exit_code = 7;
        goto cleanup;
    }
    fprintf(stderr, "Publishing audio metrics to %s\n", metricsPublisher.name);

    atomic_store(&g_last_read_ms, monotonic_ms());
    watchdog_started = pthread_create(&watchdog_thread, NULL, capture_watchdog, NULL) == 0;
    if (!watchdog_started)
    {
        fprintf(stderr, "Could not start capture watchdog, running without stall recovery\n");
    }

    while (running)
    {
        error = Pa_ReadStream(stream, buffer, frames_per_buffer);
        if (error != paNoError && error != paInputOverflowed)
        {
            fprintf(stderr, "Capture read failed: %s, reopening input stream\n", Pa_GetErrorText(error));
            PaStream* failed_stream = capture_stream_take(&g_stream_handle);
            if (failed_stream != NULL)
            {
                Pa_AbortStream(failed_stream);
                Pa_CloseStream(failed_stream);
            }
            error = Pa_OpenStream(&stream, &input_parameters, NULL, 48000, frames_per_buffer, paClipOff, NULL, NULL);
            if (error == paNoError)
                error = Pa_StartStream(stream);
            if (error != paNoError)
            {
                fprintf(stderr, "Capture stream reopen failed: %s\n", Pa_GetErrorText(error));
                exit_code = 5;
                break;
            }
            capture_stream_replace(&g_stream_handle, stream);
            atomic_store(&g_last_read_ms, monotonic_ms());
            continue;
        }
        atomic_store(&g_last_read_ms, monotonic_ms());

        SnapcastChannelMetrics leftMetrics = {0};
        SnapcastChannelMetrics rightMetrics = {0};
        audioMetricsCalculateChannel(buffer, frames_per_buffer, 0, 2, &leftMetrics);
        audioMetricsCalculateChannel(buffer, frames_per_buffer, 1, 2, &rightMetrics);
        audioMetricsPublisherPublish(&metricsPublisher, &leftMetrics, &rightMetrics, 48000);

        if (use_fifos)
        {
            extractChannelS24In32(buffer, left, 480, AUDIO_CHANNEL_LEFT);
            extractChannelS24In32(buffer, right, 480, AUDIO_CHANNEL_RIGHT);
            if (!write_channel(&left_fd, outputs.left_fifo, left, sizeof(left)))
            {
                exit_code = 6;
                break;
            }
            if (!write_channel(&right_fd, outputs.right_fifo, right, sizeof(right)))
            {
                exit_code = 6;
                break;
            }
        }
        else
        {
            floatToS24In32(buffer, pcm24, 480 * 2);
            if (fwrite(pcm24, sizeof(pcm24), 1, stdout) != 1)
            {
                exit_code = 6;
                break;
            }
        }
    }

cleanup:
    running = 0;
    if (watchdog_started)
        pthread_join(watchdog_thread, NULL);
    audioMetricsPublisherClose(&metricsPublisher);
    PaStream* final_stream = capture_stream_take(&g_stream_handle);
    if (final_stream != NULL)
    {
        Pa_StopStream(final_stream);
        Pa_CloseStream(final_stream);
    }
    if (g_stream_handle_initialized)
        capture_stream_destroy(&g_stream_handle);
    Pa_Terminate();
    if (left_fd >= 0)
        close(left_fd);
    if (right_fd >= 0)
        close(right_fd);
    return exit_code;
}
