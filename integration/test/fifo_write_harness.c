/*
 * Test harness for integration/capture/fifo_io.h.
 * Exercises writeFully() against a non-blocking FIFO with a delayed reader:
 * the pipe fills up (EAGAIN), poll(POLLOUT) waits, the reader drains, and the
 * remaining bytes must be written without losing data.
 *
 * Usage: fifo_write_harness <fifo-path> <total-bytes>
 * Exit 0 on success, non-zero on failure.
 */
#include "fifo_io.h"

#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

int main(int argc, char** argv)
{
    if (argc != 3)
    {
        fprintf(stderr, "usage: %s <fifo-path> <total-bytes>\n", argv[0]);
        return 2;
    }
    const char* fifo_path = argv[1];
    long total = strtol(argv[2], NULL, 10);
    if (total <= 0)
    {
        fprintf(stderr, "invalid byte count\n");
        return 2;
    }

    char* payload = malloc((size_t)total);
    if (payload == NULL)
        return 4;
    for (long i = 0; i < total; ++i)
        payload[i] = (char)(i % 251);

    /* Fork a reader that attaches immediately but starts reading late,
     * forcing the writer into EAGAIN + poll(POLLOUT). */
    pid_t child = fork();
    if (child < 0)
        return 5;
    if (child == 0)
    {
        int rfd = open(fifo_path, O_RDONLY | O_NONBLOCK);
        if (rfd < 0)
            _exit(11);
        usleep(150000); /* 150ms: let the writer fill the pipe first */
        long received = 0;
        char buf[4096];
        while (received < total)
        {
            ssize_t n = read(rfd, buf, sizeof(buf));
            if (n > 0)
            {
                for (ssize_t i = 0; i < n; ++i)
                {
                    if (buf[i] != (char)((received + i) % 251))
                        _exit(12); /* data corruption */
                }
                received += n;
            }
            else if (n < 0 && (errno == EAGAIN || errno == EINTR))
                usleep(10000);
            else if (n == 0)
                usleep(10000);
        }
        close(rfd);
        _exit(0);
    }

    /* Non-blocking writer open: retry until the child reader attaches
     * (ENXIO), mirroring open_fifo_writer() in the patched capture process. */
    int fd = -1;
    for (int attempt = 0; attempt < 50; ++attempt)
    {
        fd = open(fifo_path, O_WRONLY | O_NONBLOCK);
        if (fd >= 0)
            break;
        if (errno != ENXIO)
        {
            perror("open fifo");
            return 3;
        }
        usleep(20000);
    }
    if (fd < 0)
    {
        fprintf(stderr, "reader never attached to FIFO\n");
        return 3;
    }

    bool ok = writeFully(fd, payload, (size_t)total);
    close(fd);

    int status = 0;
    waitpid(child, &status, 0);
    free(payload);

    if (!ok)
    {
        fprintf(stderr, "writeFully failed\n");
        return 6;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
    {
        fprintf(stderr, "reader validation failed (status=%d)\n", status);
        return 7;
    }
    printf("fifo write recovery ok (%ld bytes)\n", total);
    return 0;
}
