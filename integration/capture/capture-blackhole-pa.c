#include <portaudio.h>

#include "fifo_io.h"
#include "pcm24.h"

#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static volatile sig_atomic_t running = 1;

typedef struct
{
    const char* left_fifo;
    const char* right_fifo;
} CaptureOutputs;

static void stop_capture(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static int parse_outputs(int argc, char** argv, CaptureOutputs* outputs)
{
    outputs->left_fifo = NULL;
    outputs->right_fifo = NULL;

    for (int i = 1; i < argc; ++i)
    {
        if ((strcmp(argv[i], "--left-fifo") == 0) && (i + 1 < argc))
            outputs->left_fifo = argv[++i];
        else if ((strcmp(argv[i], "--right-fifo") == 0) && (i + 1 < argc))
            outputs->right_fifo = argv[++i];
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
        left_fd = open(outputs.left_fifo, O_WRONLY);
        right_fd = open(outputs.right_fifo, O_WRONLY);
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

    if (left_fd >= 0)
        fprintf(stderr, "Capturing %s at 48000 Hz into left/right 24-bit PCM FIFOs, 10 ms buffers\n", info->name);
    else
        fprintf(stderr, "Capturing %s at 48000 Hz, stereo float32 -> 24-bit PCM, 10 ms buffers\n", info->name);

    float buffer[480 * 2];
    int32_t pcm24[480 * 2];
    int32_t left[480];
    int32_t right[480];
    int exit_code = 0;
    while (running)
    {
        error = Pa_ReadStream(stream, buffer, frames_per_buffer);
        if (error != paNoError && error != paInputOverflowed)
        {
            fprintf(stderr, "Capture read failed: %s\n", Pa_GetErrorText(error));
            exit_code = 5;
            break;
        }

        if (left_fd >= 0)
        {
            extractChannelS24In32(buffer, left, 480, AUDIO_CHANNEL_LEFT);
            extractChannelS24In32(buffer, right, 480, AUDIO_CHANNEL_RIGHT);
            if (!writeFully(left_fd, left, sizeof(left)))
            {
                fprintf(stderr, "Left FIFO write failed\n");
                exit_code = 6;
                break;
            }
            if (!writeFully(right_fd, right, sizeof(right)))
            {
                fprintf(stderr, "Right FIFO write failed\n");
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

    Pa_StopStream(stream);
    Pa_CloseStream(stream);
    Pa_Terminate();
    if (left_fd >= 0)
        close(left_fd);
    if (right_fd >= 0)
        close(right_fd);
    return exit_code;
}
