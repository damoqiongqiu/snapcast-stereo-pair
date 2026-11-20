#pragma once

#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <unistd.h>

static inline bool writeFully(int fd, const void* data, size_t bytes)
{
    const char* cursor = (const char*)data;
    while (bytes > 0)
    {
        const ssize_t written = write(fd, cursor, bytes);
        if (written < 0)
        {
            if (errno == EINTR)
                continue;
            return false;
        }
        if (written == 0)
            return false;
        cursor += written;
        bytes -= (size_t)written;
    }
    return true;
}
