/*
 * Set or read a CoreAudio output device's virtual main volume by device UID.
 *
 * The source Mac uses BlackHole for capture while the local Snapclient renders
 * to the built-in speaker. macOS exposes those as separate volume controls, so
 * a normal "system volume" change can attenuate the wrong stage of the path.
 */

#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const AudioObjectPropertySelector kVirtualMainVolume = 'vmvc';
static const AudioObjectPropertySelector kMainVolume = 'volm';

static void print_usage(FILE* stream, const char* program)
{
    fprintf(stream,
            "Usage:\n"
            "  %s get <device-uid>\n"
            "  %s set <device-uid> <percent>\n"
            "  %s inspect <device-uid>\n",
            program,
            program,
            program);
}

static AudioDeviceID device_for_uid(const char* uid)
{
    CFStringRef uid_string = CFStringCreateWithCString(kCFAllocatorDefault, uid, kCFStringEncodingUTF8);
    if (uid_string == NULL)
        return kAudioObjectUnknown;

    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyTranslateUIDToDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain,
    };
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    OSStatus status = AudioObjectGetPropertyData(
        kAudioObjectSystemObject, &address, sizeof(uid_string), &uid_string, &size, &device);
    CFRelease(uid_string);

    if (status != noErr)
    {
        fprintf(stderr, "Could not resolve device UID '%s': OSStatus %d\n", uid, status);
        return kAudioObjectUnknown;
    }
    return device;
}

static AudioObjectPropertyAddress volume_address(AudioObjectPropertySelector selector, AudioObjectPropertyElement element)
{
    AudioObjectPropertyAddress address = {
        selector,
        kAudioObjectPropertyScopeOutput,
        element,
    };
    return address;
}

static int read_volume_property(
    AudioDeviceID device, AudioObjectPropertySelector selector, Float32* volume)
{
    AudioObjectPropertyAddress address = volume_address(selector, kAudioObjectPropertyElementMain);
    if (AudioObjectHasProperty(device, &address))
    {
        UInt32 size = sizeof(*volume);
        return AudioObjectGetPropertyData(device, &address, 0, NULL, &size, volume) == noErr;
    }

    int found = 0;
    Float32 minimum = 1.0f;
    for (AudioObjectPropertyElement element = 1; element <= 64; ++element)
    {
        address.mElement = element;
        if (!AudioObjectHasProperty(device, &address))
            continue;

        Float32 channel_volume = 0;
        UInt32 size = sizeof(channel_volume);
        if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &channel_volume) == noErr)
        {
            minimum = channel_volume < minimum ? channel_volume : minimum;
            found = 1;
        }
    }

    if (found)
        *volume = minimum;
    return found;
}

static int write_volume_property(
    AudioDeviceID device, AudioObjectPropertySelector selector, Float32 volume)
{
    AudioObjectPropertyAddress address = volume_address(selector, kAudioObjectPropertyElementMain);
    if (AudioObjectHasProperty(device, &address))
        return AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(volume), &volume) == noErr;

    int found = 0;
    for (AudioObjectPropertyElement element = 1; element <= 64; ++element)
    {
        address.mElement = element;
        if (!AudioObjectHasProperty(device, &address))
            continue;

        OSStatus status = AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(volume), &volume);
        if (status != noErr)
            return 0;
        found = 1;
    }
    return found;
}

static int read_effective_volume(const char* uid)
{
    AudioDeviceID device = device_for_uid(uid);
    if (device == kAudioObjectUnknown)
        return 1;

    Float32 virtual_main = 0;
    Float32 main = 0;
    const int has_virtual = read_volume_property(device, kVirtualMainVolume, &virtual_main);
    const int has_main = read_volume_property(device, kMainVolume, &main);
    if (!has_virtual && !has_main)
    {
        fprintf(stderr, "Device '%s' has no writable main volume control\n", uid);
        return 1;
    }

    Float32 effective = 1.0f;
    if (has_virtual && virtual_main < effective)
        effective = virtual_main;
    if (has_main && main < effective)
        effective = main;

    printf("%.2f\n", effective * 100.0);
    return 0;
}

static int inspect_volume(const char* uid)
{
    AudioDeviceID device = device_for_uid(uid);
    if (device == kAudioObjectUnknown)
        return 1;

    Float32 virtual_main = 0;
    Float32 main = 0;
    const int has_virtual = read_volume_property(device, kVirtualMainVolume, &virtual_main);
    const int has_main = read_volume_property(device, kMainVolume, &main);
    if (!has_virtual && !has_main)
    {
        fprintf(stderr, "Device '%s' has no writable main volume control\n", uid);
        return 1;
    }

    if (has_virtual)
        printf("virtual_main=%.2f\n", virtual_main * 100.0);
    if (has_main)
        printf("main=%.2f\n", main * 100.0);
    return 0;
}

static int set_volume(const char* uid, const char* percent_text)
{
    char* end = NULL;
    errno = 0;
    double percent = strtod(percent_text, &end);
    if (errno != 0 || end == percent_text || *end != '\0' || percent < 0 || percent > 100)
    {
        fprintf(stderr, "Volume must be a percentage between 0 and 100\n");
        return 2;
    }

    AudioDeviceID device = device_for_uid(uid);
    if (device == kAudioObjectUnknown)
        return 1;

    Float32 volume = (Float32)(percent / 100.0);
    const int virtual_set = write_volume_property(device, kVirtualMainVolume, volume);
    const int main_set = write_volume_property(device, kMainVolume, volume);
    if (!virtual_set && !main_set)
    {
        fprintf(stderr, "Could not set volume for '%s'\n", uid);
        return 1;
    }

    Float32 readback = 0;
    if (virtual_set &&
        (!read_volume_property(device, kVirtualMainVolume, &readback) || readback < volume - 0.001f || readback > volume + 0.001f))
    {
        fprintf(stderr, "Could not verify virtual main volume for '%s'\n", uid);
        return 1;
    }
    if (main_set &&
        (!read_volume_property(device, kMainVolume, &readback) || readback < volume - 0.001f || readback > volume + 0.001f))
    {
        fprintf(stderr, "Could not verify main volume for '%s'\n", uid);
        return 1;
    }

    return 0;
}

int main(int argc, char** argv)
{
    if (argc == 2 && strcmp(argv[1], "--help") == 0)
    {
        print_usage(stdout, argv[0]);
        return 0;
    }
    if (argc == 3 && strcmp(argv[1], "get") == 0)
        return read_effective_volume(argv[2]);
    if (argc == 3 && strcmp(argv[1], "inspect") == 0)
        return inspect_volume(argv[2]);
    if (argc == 4 && strcmp(argv[1], "set") == 0)
        return set_volume(argv[2], argv[3]);

    print_usage(stderr, argv[0]);
    return 2;
}
