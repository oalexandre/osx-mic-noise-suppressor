#ifndef SHM_BRIDGE_H
#define SHM_BRIDGE_H

#include <stddef.h>

// Wrapper functions for POSIX shared memory
// Needed because Swift can't directly call variadic functions

int shm_open_wrapper(const char *name, int oflag, int mode);
int shm_unlink_wrapper(const char *name);
void *mmap_wrapper(void *addr, size_t len, int prot, int flags, int fd, long offset);
int munmap_wrapper(void *addr, size_t len);
int ftruncate_wrapper(int fd, long length);
int close_wrapper(int fd);
const char *strerror_wrapper(int errnum);
int get_errno(void);

#endif
