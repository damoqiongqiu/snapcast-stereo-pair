#include "capture_watchdog.h"

#include <stdio.h>

static int failures = 0;

static void expect_decision(
    const char* name,
    CaptureWatchdogDecision actual,
    CaptureWatchdogDecision expected)
{
    if (actual != expected)
    {
        fprintf(stderr, "%s: expected %d, got %d\n", name, (int)expected, (int)actual);
        ++failures;
    }
}

int main(void)
{
    expect_decision(
        "fresh",
        capture_watchdog_decide(1500, 1000),
        CAPTURE_WATCHDOG_NONE);
    expect_decision(
        "stalled",
        capture_watchdog_decide(2001, 1000),
        CAPTURE_WATCHDOG_ABORT);
    expect_decision(
        "abort timeout",
        capture_watchdog_decide(4002, 1000),
        CAPTURE_WATCHDOG_EXIT_PROCESS);

    CaptureStreamHandle handle;
    if (!capture_stream_init(&handle))
    {
        fprintf(stderr, "failed to initialize stream handle\n");
        return 1;
    }
    if (capture_stream_abort(&handle))
    {
        fprintf(stderr, "empty stream abort must be a no-op\n");
        ++failures;
    }
    capture_stream_destroy(&handle);

    if (failures != 0)
        return 1;
    printf("watchdog decision harness passed\n");
    return 0;
}
