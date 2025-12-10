#include "shm_bridge.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

int shm_open_wrapper(const char *name, int oflag, int mode) {
    return shm_open(name, oflag, (mode_t)mode);
}

int shm_unlink_wrapper(const char *name) {
    return shm_unlink(name);
}

void *mmap_wrapper(void *addr, size_t len, int prot, int flags, int fd, long offset) {
    return mmap(addr, len, prot, flags, fd, (off_t)offset);
}

int munmap_wrapper(void *addr, size_t len) {
    return munmap(addr, len);
}

int ftruncate_wrapper(int fd, long length) {
    return ftruncate(fd, (off_t)length);
}

int close_wrapper(int fd) {
    return close(fd);
}

const char *strerror_wrapper(int errnum) {
    return strerror(errnum);
}

int get_errno(void) {
    return errno;
}
