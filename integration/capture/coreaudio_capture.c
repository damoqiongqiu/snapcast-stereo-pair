#include "coreaudio_capture.h"

#include <CoreFoundation/CoreFoundation.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static long long monotonic_ms(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static const char* requested_device_name(const CoreAudioCapture* capture)
{
    if ((capture->requested_name[0] == '\0') || (strcmp(capture->requested_name, "BlackHole 2ch") == 0))
        return "BlackHole";
    return capture->requested_name;
}

static int device_name_matches(AudioObjectID device, const char* requested)
{
    AudioObjectPropertyAddress address = {
        .mSelector = kAudioObjectPropertyName,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    CFStringRef name = NULL;
    UInt32 size = sizeof(name);
    OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &name);
    if (status != noErr || name == NULL)
        return 0;

    CFStringRef requested_string = CFStringCreateWithCString(kCFAllocatorDefault, requested, kCFStringEncodingUTF8);
    const Boolean matches =
        requested_string != NULL && CFStringFind(name, requested_string, kCFCompareCaseInsensitive).location != kCFNotFound;
    if (requested_string != NULL)
        CFRelease(requested_string);
    CFRelease(name);
    return matches ? 1 : 0;
}

static int find_device(const char* requested, AudioObjectID* device_out)
{
    AudioObjectPropertyAddress address = {
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size);
    if (status != noErr || size == 0)
        return 1;

    AudioObjectID* devices = calloc(1, size);
    if (devices == NULL)
        return 2;
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices);
    if (status != noErr)
    {
        free(devices);
        return 3;
    }

    int result = 4;
    const size_t count = size / sizeof(*devices);
    for (size_t index = 0; index < count; ++index)
    {
        if (device_name_matches(devices[index], requested))
        {
            *device_out = devices[index];
            result = 0;
            break;
        }
    }
    free(devices);
    return result;
}

static int validate_input_format(AudioObjectID device)
{
    AudioObjectPropertyAddress streams_address = {
        .mSelector = kAudioDevicePropertyStreams,
        .mScope = kAudioObjectPropertyScopeInput,
        .mElement = kAudioObjectPropertyElementMain,
    };
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(device, &streams_address, 0, NULL, &size);
    if (status != noErr || size < sizeof(AudioStreamID))
        return 1;

    AudioStreamID stream = kAudioObjectUnknown;
    UInt32 stream_size = sizeof(stream);
    status = AudioObjectGetPropertyData(device, &streams_address, 0, NULL, &stream_size, &stream);
    if (status != noErr || stream == kAudioObjectUnknown)
        return 2;

    AudioObjectPropertyAddress format_address = {
        .mSelector = kAudioStreamPropertyVirtualFormat,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    AudioStreamBasicDescription format;
    UInt32 format_size = sizeof(format);
    status = AudioObjectGetPropertyData(stream, &format_address, 0, NULL, &format_size, &format);
    if (status != noErr)
        return 3;
    if (fabs(format.mSampleRate - 48000.0) > 0.5 || format.mChannelsPerFrame != 2)
        return 4;
    if ((format.mFormatID != kAudioFormatLinearPCM) || (format.mBitsPerChannel != 32) ||
        ((format.mFormatFlags & kAudioFormatFlagIsFloat) == 0))
        return 5;
    return 0;
}

static OSStatus capture_io_proc(
    AudioObjectID device,
    const AudioTimeStamp* now,
    const AudioBufferList* input,
    const AudioTimeStamp* input_time,
    AudioBufferList* output,
    const AudioTimeStamp* output_time,
    void* context)
{
    (void)device;
    (void)now;
    (void)input_time;
    (void)output;
    (void)output_time;

    CoreAudioCapture* capture = context;
    atomic_store_explicit(&capture->callback_ms, monotonic_ms(), memory_order_release);
    atomic_fetch_add_explicit(&capture->callback_count, 1, memory_order_relaxed);
    if ((input == NULL) || (input->mNumberBuffers == 0) || (input->mBuffers[0].mData == NULL))
        return noErr;

    bool pushed = false;
    if ((input->mNumberBuffers == 1) && (input->mBuffers[0].mNumberChannels >= CAPTURE_CHANNELS))
    {
        const size_t frames =
            input->mBuffers[0].mDataByteSize / (sizeof(float) * input->mBuffers[0].mNumberChannels);
        pushed = captureFrameRingPushInterleaved(capture->ring, input->mBuffers[0].mData, frames);
    }
    else if ((input->mNumberBuffers >= CAPTURE_CHANNELS) && (input->mBuffers[1].mData != NULL))
    {
        const size_t left_frames = input->mBuffers[0].mDataByteSize / sizeof(float);
        const size_t right_frames = input->mBuffers[1].mDataByteSize / sizeof(float);
        const size_t frames = left_frames < right_frames ? left_frames : right_frames;
        pushed = captureFrameRingPushPlanar(
            capture->ring, input->mBuffers[0].mData, input->mBuffers[1].mData, frames);
    }
    if (!pushed)
        atomic_fetch_add_explicit(&capture->push_failures, 1, memory_order_relaxed);
    return noErr;
}

static int start_device(CoreAudioCapture* capture)
{
    OSStatus status =
        AudioDeviceCreateIOProcID(capture->device_id, capture_io_proc, capture, &capture->proc_id);
    if (status != noErr)
        return 1;
    status = AudioDeviceStart(capture->device_id, capture->proc_id);
    if (status != noErr)
    {
        AudioDeviceDestroyIOProcID(capture->device_id, capture->proc_id);
        capture->proc_id = NULL;
        return 2;
    }
    capture->started = true;
    return 0;
}

static void stop_device(CoreAudioCapture* capture)
{
    if ((capture == NULL) || (capture->device_id == kAudioObjectUnknown))
        return;
    if (capture->proc_id != NULL)
    {
        if (capture->started)
            AudioDeviceStop(capture->device_id, capture->proc_id);
        AudioDeviceDestroyIOProcID(capture->device_id, capture->proc_id);
        capture->proc_id = NULL;
    }
    capture->started = false;
}

int coreAudioCaptureOpen(CoreAudioCapture* capture, const char* requested_name, CaptureFrameRing* ring)
{
    if ((capture == NULL) || (ring == NULL))
        return 1;
    memset(capture, 0, sizeof(*capture));
    capture->device_id = kAudioObjectUnknown;
    capture->ring = ring;
    atomic_init(&capture->callback_ms, 0);
    atomic_init(&capture->callback_count, 0);
    atomic_init(&capture->push_failures, 0);
    const char* requested = (requested_name == NULL || *requested_name == '\0') ? "BlackHole 2ch" : requested_name;
    snprintf(capture->requested_name, sizeof(capture->requested_name), "%s", requested);

    int result = find_device(requested_device_name(capture), &capture->device_id);
    if (result != 0)
        return 10 + result;
    result = validate_input_format(capture->device_id);
    if (result != 0)
    {
        capture->device_id = kAudioObjectUnknown;
        return 20 + result;
    }
    result = start_device(capture);
    if (result != 0)
    {
        capture->device_id = kAudioObjectUnknown;
        return 30 + result;
    }
    return 0;
}

int coreAudioCaptureRestart(CoreAudioCapture* capture)
{
    if (capture == NULL)
        return 1;
    stop_device(capture);
    int result = find_device(requested_device_name(capture), &capture->device_id);
    if (result != 0)
        return 10 + result;
    result = validate_input_format(capture->device_id);
    if (result != 0)
    {
        capture->device_id = kAudioObjectUnknown;
        return 20 + result;
    }
    result = start_device(capture);
    if (result != 0)
    {
        capture->device_id = kAudioObjectUnknown;
        return 30 + result;
    }
    return 0;
}

void coreAudioCaptureClose(CoreAudioCapture* capture)
{
    if (capture == NULL)
        return;
    stop_device(capture);
    capture->device_id = kAudioObjectUnknown;
    capture->ring = NULL;
}
