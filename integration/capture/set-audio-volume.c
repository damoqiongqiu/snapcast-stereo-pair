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

static void print_usage(FILE* stream, const char* program)
{
    fprintf(stream,
            "Usage:\n"
            "  %s get <device-uid>\n"
            "  %s set <device-uid> <percent>\n",
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

static AudioObjectPropertyAddress volume_address(void)
{
    AudioObjectPropertyAddress address = {
        kVirtualMainVolume,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain,
    };
    return address;
}

static int get_volume(const char* uid)
{
    AudioDeviceID device = device_for_uid(uid);
    if (device == kAudioObjectUnknown)
        return 1;

    AudioObjectPropertyAddress address = volume_address();
    if (!AudioObjectHasProperty(device, &address))
    {
        fprintf(stderr, "Device '%s' has no virtual main volume control\n", uid);
        return 1;
    }

    Float32 volume = 0;
    UInt32 size = sizeof(volume);
    OSStatus status = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &volume);
    if (status != noErr)
    {
        fprintf(stderr, "Could not read volume for '%s': OSStatus %d\n", uid, status);
        return 1;
    }
    printf("%.2f\n", volume * 100.0);
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

    AudioObjectPropertyAddress address = volume_address();
    if (!AudioObjectHasProperty(device, &address))
    {
        fprintf(stderr, "Device '%s' has no virtual main volume control\n", uid);
        return 1;
    }

    Float32 volume = (Float32)(percent / 100.0);
    OSStatus status = AudioObjectSetPropertyData(device, &address, 0, NULL, sizeof(volume), &volume);
    if (status != noErr)
    {
        fprintf(stderr, "Could not set volume for '%s': OSStatus %d\n", uid, status);
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
        return get_volume(argv[2]);
    if (argc == 4 && strcmp(argv[1], "set") == 0)
        return set_volume(argv[2], argv[3]);

    print_usage(stderr, argv[0]);
    return 2;
}
