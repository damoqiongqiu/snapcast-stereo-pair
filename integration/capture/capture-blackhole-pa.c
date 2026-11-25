#include "audio_metrics.h"
#include "capture_clock.h"
#include "coreaudio_capture.h"
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
#include <unistd.h>

#define WRITER_PERIOD_NS (10ULL * 1000000ULL)
#define WRITER_CATCHUP_NS (200ULL * 1000000ULL)

static volatile sig_atomic_t running = 1;

typedef struct
{
    const char* left_fifo;
    const char* right_fifo;
    const char* metrics_shm;
} CaptureOutputs;

typedef struct
{
    CoreAudioCapture* capture;
    pthread_t thread;
    atomic_bool stop;
    atomic_uint recovery_attempts;
    atomic_uint successful_recoveries;
} CaptureRecovery;

static void stop_capture(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static uint64_t monotonic_ns(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
}

static long long monotonic_ms(void)
{
    return (long long)(monotonic_ns() / 1000000ULL);
}

static void sleep_for_ns(uint64_t duration)
{
    struct timespec request = {
        .tv_sec = (time_t)(duration / 1000000000ULL),
        .tv_nsec = (long)(duration % 1000000000ULL),
    };
    while (nanosleep(&request, &request) != 0 && errno == EINTR && running)
    {
    }
}

static void sleep_until_ns(uint64_t deadline)
{
    uint64_t now = monotonic_ns();
    while (running && now < deadline)
    {
        sleep_for_ns(deadline - now);
        now = monotonic_ns();
    }
}

static int open_fifo_writer(const char* path)
{
    for (;;)
    {
        int fd = open(path, O_WRONLY | O_NONBLOCK);
        if (fd >= 0)
            return fd;
        if ((errno == ENXIO || errno == ENOENT) && running)
        {
            sleep_for_ns(200ULL * 1000000ULL);
            continue;
        }
        return -1;
    }
}

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
        sleep_for_ns(100ULL * 1000000ULL);
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

static bool write_stereo_split(
    const float* block,
    size_t frames,
    bool use_fifos,
    int* left_fd,
    int* right_fd,
    const CaptureOutputs* outputs)
{
    int32_t left[CAPTURE_BLOCK_FRAMES];
    int32_t right[CAPTURE_BLOCK_FRAMES];
    extractChannelS24In32(block, left, frames, AUDIO_CHANNEL_LEFT);
    extractChannelS24In32(block, right, frames, AUDIO_CHANNEL_RIGHT);

    if (use_fifos)
    {
        if (!write_channel(left_fd, outputs->left_fifo, left, frames * sizeof(left[0])))
            return false;
        return write_channel(right_fd, outputs->right_fifo, right, frames * sizeof(right[0]));
    }

    int32_t pcm24[CAPTURE_BLOCK_FRAMES * CAPTURE_CHANNELS];
    floatToS24In32(block, pcm24, frames * CAPTURE_CHANNELS);
    return fwrite(pcm24, sizeof(pcm24[0]), frames * CAPTURE_CHANNELS, stdout) == frames * CAPTURE_CHANNELS;
}

static void* capture_recovery_thread(void* argument)
{
    CaptureRecovery* recovery = argument;
    long long last_attempt_ms = 0;
    while (running && !atomic_load_explicit(&recovery->stop, memory_order_acquire))
    {
        sleep_for_ns(200ULL * 1000000ULL);
        if (!running || atomic_load_explicit(&recovery->stop, memory_order_acquire))
            break;

        const long long now = monotonic_ms();
        const long long last_callback =
            atomic_load_explicit(&recovery->capture->callback_ms, memory_order_acquire);
        const CaptureWatchdogDecision decision = capture_watchdog_decide(now, last_callback);
        if ((decision == CAPTURE_WATCHDOG_RECOVER) &&
            capture_watchdog_should_attempt_recovery(now, last_attempt_ms))
        {
            last_attempt_ms = now;
            const unsigned attempt =
                atomic_fetch_add_explicit(&recovery->recovery_attempts, 1, memory_order_relaxed) + 1;
            fprintf(stderr, "CoreAudio callback heartbeat stalled; recovery attempt %u\n", attempt);
            const int result = coreAudioCaptureRestart(recovery->capture);
            if (result == 0)
            {
                atomic_fetch_add_explicit(
                    &recovery->successful_recoveries, 1, memory_order_relaxed);
                fprintf(stderr, "CoreAudio capture restart accepted; waiting for callbacks\n");
            }
            else
            {
                fprintf(stderr, "CoreAudio capture restart failed with code %d\n", result);
            }
        }
        else if (decision == CAPTURE_WATCHDOG_EXIT_PROCESS)
        {
            fprintf(stderr, "CoreAudio callbacks did not recover after %lld ms\n", now - last_callback);
        }
    }
    return NULL;
}

static bool start_recovery(CaptureRecovery* recovery, CoreAudioCapture* capture)
{
    memset(recovery, 0, sizeof(*recovery));
    recovery->capture = capture;
    atomic_init(&recovery->stop, false);
    atomic_init(&recovery->recovery_attempts, 0);
    atomic_init(&recovery->successful_recoveries, 0);
    return pthread_create(&recovery->thread, NULL, capture_recovery_thread, recovery) == 0;
}

static void stop_recovery(CaptureRecovery* recovery)
{
    atomic_store_explicit(&recovery->stop, true, memory_order_release);
    pthread_join(recovery->thread, NULL);
}

int main(int argc, char** argv)
{
    CaptureOutputs outputs;
    if (parse_outputs(argc, argv, &outputs) != 0)
    {
        fprintf(stderr, "Usage: %s [--left-fifo PATH --right-fifo PATH] [--metrics-shm NAME]\n", argv[0]);
        return 2;
    }

    signal(SIGINT, stop_capture);
    signal(SIGTERM, stop_capture);
    signal(SIGPIPE, SIG_IGN);
    setvbuf(stdout, NULL, _IONBF, 0);

    int left_fd = -1;
    int right_fd = -1;
    const bool use_fifos = outputs.left_fifo != NULL;
    if (use_fifos)
    {
        left_fd = open_fifo_writer(outputs.left_fifo);
        right_fd = left_fd >= 0 ? open_fifo_writer(outputs.right_fifo) : -1;
        if (left_fd < 0 || right_fd < 0)
        {
            fprintf(stderr, "Could not open capture FIFOs\n");
            if (left_fd >= 0)
                close(left_fd);
            if (right_fd >= 0)
                close(right_fd);
            return 3;
        }
    }

    SnapcastAudioMetricsPublisher metricsPublisher = {.fd = -1, .metrics = NULL};
    if (!audioMetricsPublisherOpen(&metricsPublisher, outputs.metrics_shm))
    {
        fprintf(stderr, "Could not open shared audio metrics: %s\n", strerror(errno));
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 7;
    }

    CaptureFrameRing ring;
    captureFrameRingInit(&ring);
    CoreAudioCapture capture;
    const char* requested = getenv("CAPTURE_DEVICE");
    if (requested == NULL || *requested == '\0')
        requested = "BlackHole 2ch";
    const int capture_result = coreAudioCaptureOpen(&capture, requested, &ring);
    if (capture_result != 0)
    {
        fprintf(stderr, "Could not open CoreAudio capture device %s: code %d\n", requested, capture_result);
        audioMetricsPublisherClose(&metricsPublisher);
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 4;
    }

    if (atomic_load_explicit(&capture.callback_ms, memory_order_acquire) <= 0)
        atomic_store_explicit(&capture.callback_ms, monotonic_ms(), memory_order_release);

    fprintf(stderr, "Capturing BlackHole through CoreAudio callback at 48000 Hz\n");
    fprintf(stderr, "Writing continuous left/right 24-bit PCM with 10 ms blocks\n");
    fprintf(stderr, "Publishing audio metrics to %s\n", metricsPublisher.name);

    CaptureRecovery recovery;
    if (!start_recovery(&recovery, &capture))
    {
        fprintf(stderr, "Could not start capture recovery thread\n");
        coreAudioCaptureClose(&capture);
        audioMetricsPublisherClose(&metricsPublisher);
        if (left_fd >= 0)
            close(left_fd);
        if (right_fd >= 0)
            close(right_fd);
        return 5;
    }

    int exit_code = 0;
    uint64_t next_deadline = monotonic_ns();
    uint64_t catchup_count = 0;
    uint64_t generated_silence_cycles = 0;
    uint64_t dropped_frames = 0;
    uint64_t last_metrics_publish = 0;
    while (running)
    {
        const long long now_ms = monotonic_ms();
        const long long callback_ms = atomic_load_explicit(&capture.callback_ms, memory_order_acquire);
        if (callback_ms > 0 && capture_watchdog_decide(now_ms, callback_ms) == CAPTURE_WATCHDOG_EXIT_PROCESS)
        {
            fprintf(stderr, "CoreAudio callbacks did not recover after %lld ms, exiting\n", now_ms - callback_ms);
            exit_code = 10;
            break;
        }

        float block[CAPTURE_BLOCK_FRAMES * CAPTURE_CHANNELS];
        const CaptureClockBlock selected =
            captureClockNextBlock(&ring, block, CAPTURE_BLOCK_FRAMES, CAPTURE_MAX_BACKLOG_FRAMES);
        if (!selected.has_audio)
            ++generated_silence_cycles;
        dropped_frames += selected.dropped_frames;
        if (!write_stereo_split(block, selected.frames, use_fifos, &left_fd, &right_fd, &outputs))
        {
            exit_code = 6;
            break;
        }

        next_deadline += WRITER_PERIOD_NS;
        const uint64_t now = monotonic_ns();
        if (now - last_metrics_publish >= 20ULL * 1000000ULL)
        {
            SnapcastChannelMetrics leftMetrics = {0};
            SnapcastChannelMetrics rightMetrics = {0};
            audioMetricsCalculateChannel(block, selected.frames, 0, CAPTURE_CHANNELS, &leftMetrics);
            audioMetricsCalculateChannel(block, selected.frames, 1, CAPTURE_CHANNELS, &rightMetrics);
            const SnapcastCaptureMetrics captureMetrics = {
                .callback_count =
                    atomic_load_explicit(&capture.callback_count, memory_order_acquire),
                .generated_silence_cycles = generated_silence_cycles,
                .dropped_frames = dropped_frames,
                .recovery_attempts =
                    atomic_load_explicit(&recovery.recovery_attempts, memory_order_relaxed),
                .successful_recoveries =
                    atomic_load_explicit(&recovery.successful_recoveries, memory_order_relaxed),
            };
            audioMetricsPublisherPublish(
                &metricsPublisher, &leftMetrics, &rightMetrics, 48000, &captureMetrics);
            last_metrics_publish = now;
        }

        if (now > next_deadline + WRITER_CATCHUP_NS)
        {
            ++catchup_count;
            next_deadline = now;
        }
        else
        {
            sleep_until_ns(next_deadline);
        }
    }

    running = 0;
    if (exit_code == 10)
        _exit(exit_code);
    stop_recovery(&recovery);
    coreAudioCaptureClose(&capture);
    audioMetricsPublisherClose(&metricsPublisher);
    if (left_fd >= 0)
        close(left_fd);
    if (right_fd >= 0)
        close(right_fd);

    if (catchup_count > 0)
        fprintf(stderr, "Writer recovered from %llu scheduling catch-up events\n", (unsigned long long)catchup_count);
    return exit_code;
}
