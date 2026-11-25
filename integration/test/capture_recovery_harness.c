#include "capture_clock.h"

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
    expect_decision("fresh", capture_watchdog_decide(3999, 2000), CAPTURE_WATCHDOG_NONE);
    expect_decision("idle within recovery deadline", capture_watchdog_decide(4001, 2000), CAPTURE_WATCHDOG_RECOVER);
    expect_decision("recovery exhausted", capture_watchdog_decide(17001, 2000), CAPTURE_WATCHDOG_EXIT_PROCESS);

    if (!capture_watchdog_should_attempt_recovery(2500, 0))
    {
        fprintf(stderr, "first recovery must be allowed immediately\n");
        ++failures;
    }
    if (capture_watchdog_should_attempt_recovery(3999, 2500))
    {
        fprintf(stderr, "recovery must be rate limited\n");
        ++failures;
    }
    if (!capture_watchdog_should_attempt_recovery(4500, 2500))
    {
        fprintf(stderr, "recovery must resume after its interval\n");
        ++failures;
    }

    if (failures != 0)
        return 1;
    printf("watchdog decision harness passed\n");
    return 0;
}
