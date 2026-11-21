#include "StereoPairMetricsBridge.h"

#include <fcntl.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

int snapcast_metrics_open_readonly(void)
{
    char name[96];
    snprintf(name, sizeof(name), "/snapcast-stereo-metrics-%u", (unsigned)getuid());
    return shm_open(name, O_RDONLY, 0);
}
