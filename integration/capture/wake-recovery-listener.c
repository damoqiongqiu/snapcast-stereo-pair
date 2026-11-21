#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

extern char** environ;

static io_connect_t root_port = MACH_PORT_NULL;
static io_object_t power_notifier = IO_OBJECT_NULL;
static IONotificationPortRef notification_port = NULL;
static const char* recovery_script = NULL;
static volatile sig_atomic_t running = 1;

static void stop_listener(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static void run_recovery(void)
{
    pid_t child = 0;
    char* argv[] = {(char*)recovery_script, NULL};
    int error = posix_spawn(&child, recovery_script, NULL, NULL, argv, environ);
    if (error != 0)
        fprintf(stderr, "Could not start wake recovery script '%s': error %d\n", recovery_script, error);
}

static void power_callback(
    void* context, io_service_t service, natural_t message_type, void* message_argument)
{
    (void)context;
    (void)service;

    if (message_type == kIOMessageCanSystemSleep || message_type == kIOMessageSystemWillSleep)
    {
        IOAllowPowerChange(root_port, (long)message_argument);
    }
    else if (message_type == kIOMessageSystemHasPoweredOn)
    {
        run_recovery();
    }
}

int main(int argc, char** argv)
{
    if (argc != 2)
    {
        fprintf(stderr, "Usage: %s <wake-recovery-script>\n", argv[0]);
        return 2;
    }

    recovery_script = argv[1];
    signal(SIGINT, stop_listener);
    signal(SIGTERM, stop_listener);

    io_object_t notifier = IO_OBJECT_NULL;
    root_port = IORegisterForSystemPower(&power_notifier, &notification_port, power_callback, &notifier);
    if (root_port == MACH_PORT_NULL)
    {
        fprintf(stderr, "Could not register for system power notifications\n");
        return 1;
    }
    power_notifier = notifier;

    CFRunLoopSourceRef source = IONotificationPortGetRunLoopSource(notification_port);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);

    while (running)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, false);

    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    IODeregisterForSystemPower(&power_notifier);
    IONotificationPortDestroy(notification_port);
    return 0;
}
