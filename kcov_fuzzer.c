// kcov_fuzzer.c
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>

#define KCOV_INIT_TRACE _IOR('c', 1, unsigned long)
#define KCOV_ENABLE _IO('c', 100)
#define KCOV_DISABLE _IO('c', 101)

#define KCOV_TRACE_SIZE (1 << 17)  // 128 KB

static void setup_kcov(int* kcov_fd, uint64_t** trace, size_t* n_entries) {
    *kcov_fd = open("/sys/kernel/debug/kcov", O_RDWR);
    if (*kcov_fd < 0) {
        perror("open /sys/kernel/debug/kcov");
        exit(1);
    }

    if (ioctl(*kcov_fd, KCOV_INIT_TRACE, KCOV_TRACE_SIZE)) {
        perror("ioctl KCOV_INIT_TRACE");
        exit(1);
    }

    *n_entries = KCOV_TRACE_SIZE;
    *trace = (uint64_t*)mmap(NULL, KCOV_TRACE_SIZE * sizeof(uint64_t),
                             PROT_READ | PROT_WRITE, MAP_SHARED, *kcov_fd, 0);
    if (*trace == MAP_FAILED) {
        perror("mmap");
        exit(1);
    }

    if (ioctl(*kcov_fd, KCOV_ENABLE, 0)) {
        perror("ioctl KCOV_ENABLE");
        exit(1);
    }

    // Clear trace buffer
    (*trace)[0] = 0;
}

static void stop_kcov(int kcov_fd) {
    ioctl(kcov_fd, KCOV_DISABLE, 0);
    close(kcov_fd);
}

int main() {
    int kcov_fd;
    uint64_t* trace;
    size_t n_entries;

    setup_kcov(&kcov_fd, &trace, &n_entries);

    // === Target code to fuzz ===
    int dev = open("/dev/null", O_WRONLY);
    if (dev < 0) {
        perror("open /dev/null");
        exit(1);
    }

    write(dev, "fuzzdata", 8);  // Replace this with actual ioctl/fuzz input
    close(dev);
    // ===========================

    size_t num_pc = trace[0];
    printf("[+] KCOV captured %zu PCs\n", num_pc);

    stop_kcov(kcov_fd);
    return 0;
}
