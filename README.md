# Android Kernel Fuzzing Environment

This repository automates the build and boot of an **Android 12 Common (v5.10) kernel** with **KASAN/KCOV instrumentation**, plus a minimal root-fs, inside **QEMU**.

## Contents

- **`run.sh`**  
  All-in-one script that:
  1. Installs host dependencies  
  2. Clones & repo-syncs the Android “common” kernel (android12-5.10)  
  3. Fetches Google’s prebuilt Clang (clang-r522817)  
  4. Configures the kernel for KASAN, KCOV, VIRTIO, INIT_STACK_ALL_ZERO, modules, etc.  
  5. Builds the kernel and modules with LLVM/Clang  
  6. Creates a 64 MB ext4 rootfs containing BusyBox + modules  
  7. Boots the combination in QEMU, dropping to an interactive shell  

## Prerequisites

On **Ubuntu/Debian** hosts:

```
sudo apt update
sudo apt install -y \
  bc bison build-essential curl flex git libelf-dev repo \
  device-tree-compiler qemu-system-x86 wget cpio python3 unzip e2fsprogs
```

- Ensure you have **~20 GB free disk space** and **≥8 GB RAM**.

##  Usage

1. **Clone this repo**
   ```
   git clone https://github.com/rohit76549/android-driver-fuzzing
   cd android-driver-fuzzing
   ```

2. **Make `run.sh` executable**
   ```
   chmod +x run.sh
   ```

3. **Run the setup script**
   ```
   ./run.sh
   ```
   - The first run takes ~30 min to fetch sources, build the kernel, prepare rootfs, and launch QEMU.

4. **Interact in the QEMU shell**
   ```
   / # ls /dev
   console  null  random  ttyS0  urandom  vda  …
   / # uname -a
   Linux qemu 5.10.238+ #1 …
   ```

##  Manual QEMU Launch

Launched the new kernel under QEMU via:
```
qemu-system-x86_64 \
  -kernel bzImage \
  -drive file=rootfs.img,format=raw,if=virtio \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 root=/dev/vda rw init=/init nokaslr quiet selinux=0" \
  -m 1G -nographic
```

