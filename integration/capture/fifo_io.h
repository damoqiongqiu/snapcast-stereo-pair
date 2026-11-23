#pragma once

#include <errno.h>
#include <poll.h>
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
            if (errno == EAGAIN || errno == EWOULDBLOCK)
            {
                /* FIFO momentarily full: wait for the reader instead of dying */
                struct pollfd pfd = { .fd = fd, .events = POLLOUT, .revents = 0 };
                if (poll(&pfd, 1, 5000) <= 0)
                    return false;
                continue;
            }
            return false;
        }
        if (written == 0)
            return false;
        cursor += written;
        bytes -= (size_t)written;
    }
    return true;
}
