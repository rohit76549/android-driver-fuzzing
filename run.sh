#!/bin/bash
set -euo pipefail

# === CONFIG ===
WORKDIR="$PWD/android-fuzzing"
KERNEL_DIR="$WORKDIR/android-kernel"
CLANG_VERSION="clang-r522817"
CLANG_REPO="$KERNEL_DIR/prebuilts/clang/host/linux-x86/linux-x86"
TOOLCHAIN_DIR="$CLANG_REPO/$CLANG_VERSION"
BUSYBOX_URL="https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64"
BUSYBOX_BIN="$WORKDIR/busybox-x86_64"
ROOTFS_DIR="$WORKDIR/rootfs"
ROOTFS_IMG="$WORKDIR/rootfs.img"
BZIMAGE="$WORKDIR/bzImage"
QEMU_MEM=1024
QEMU_CMDLINE="console=ttyS0 root=/dev/vda rw init=/init nokaslr quiet selinux=0"

# === Host dependencies ===
echo "▶ Installing host packages..."
sudo apt-get update
sudo apt-get install -y \
  bc bison build-essential curl flex git libelf-dev \
  device-tree-compiler qemu-system-x86 wget cpio \
  python3 unzip repo e2fsprogs

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# === Download BusyBox ===
if [ ! -x "$BUSYBOX_BIN" ]; then
  echo "▶ Downloading BusyBox..."
  wget -q "$BUSYBOX_URL" -O "$BUSYBOX_BIN"
  chmod +x "$BUSYBOX_BIN"
fi

# === Clone kernel if missing ===
if [ ! -d "$KERNEL_DIR" ]; then
  echo "▶ Cloning Android common kernel..."
  git clone https://android.googlesource.com/kernel/common android-kernel
  cd "$KERNEL_DIR"
  git checkout -b android12-5.10 origin/android12-5.10
  repo init -u https://android.googlesource.com/kernel/manifest -b common-android12-5.10
  repo sync -j"$(nproc)"
else
  echo "✔ Kernel source already exists."
  cd "$KERNEL_DIR"
fi

# === Ensure Clang toolchain is present ===
if [ ! -d "$CLANG_REPO" ]; then
  echo "▶ Shallow-cloning prebuilts/clang..."
  mkdir -p "$(dirname "$CLANG_REPO")"
  git clone --depth 1 https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 "$CLANG_REPO"
fi

if [ ! -d "$TOOLCHAIN_DIR" ]; then
  echo "❌ Clang version $CLANG_VERSION not found."
  echo "   Available:"
  ls "$CLANG_REPO"
  exit 1
fi
echo "✔ Found clang at $TOOLCHAIN_DIR"

# === Kernel config ===
echo "▶ Configuring kernel..."
make ARCH=x86_64 distclean
make ARCH=x86_64 defconfig

scripts/config --enable CONFIG_KASAN \
               --enable CONFIG_KCOV \
               --disable CONFIG_STACK_VALIDATION \
               --enable CONFIG_DEBUG_INFO \
               --enable CONFIG_DEBUG_KERNEL \
               --enable CONFIG_DEBUG_MISC \
               --enable CONFIG_DEBUG_FS \
               --enable CONFIG_DEBUG_INFO_DWARF4 \
               --enable CONFIG_VIRTIO \
               --enable CONFIG_VIRTIO_PCI \
               --enable CONFIG_VIRTIO_BLK \
               --enable CONFIG_INIT_STACK_ALL_ZERO \
               --enable CONFIG_MODULES \
               --enable CONFIG_MODULE_UNLOAD \
               --enable CONFIG_DEVTMPFS \
               --enable CONFIG_DEVTMPFS_MOUNT \
               --set-val CONFIG_FRAME_WARN 8192

make ARCH=x86_64 olddefconfig

# === Build kernel + modules ===
echo "▶ Building kernel..."
export KBUILD_CFLAGS_NO_PROPAGATE="-Wno-error=frame-larger-than"
make -j"$(nproc)" \
  ARCH=x86_64 \
  LLVM=1 LLVM_IAS=1 \
  CC="$TOOLCHAIN_DIR/bin/clang"

cp arch/x86/boot/bzImage "$BZIMAGE"
echo "✔ Kernel → $BZIMAGE"

echo "▶ Installing modules to staging..."
make ARCH=x86_64 INSTALL_MOD_PATH="$WORKDIR/staging" modules_install

# === Build rootfs ===
echo "▶ Building rootfs..."
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev,tmp,root}

# Add BusyBox and link all applets
cp "$BUSYBOX_BIN" "$ROOTFS_DIR/bin/busybox"
chmod +x "$ROOTFS_DIR/bin/busybox"
pushd "$ROOTFS_DIR/bin" > /dev/null
for app in $(./busybox --list); do
  ln -sf busybox "$app"
done
popd > /dev/null
ln -sf /bin/busybox "$ROOTFS_DIR/sbin/modprobe"

# Add /init
cat > "$ROOTFS_DIR/init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs devtmpfs /dev

echo "[+] Boot successful, dropping to shell"

# Optionally load all modules
if [ -x /sbin/modprobe ]; then
  for mod in $(find /lib/modules/$(uname -r)/ -name '*.ko'); do
    insmod "$mod" 2>/dev/null || true
  done
fi

exec /bin/sh
EOF
chmod +x "$ROOTFS_DIR/init"

# Create minimal /dev
sudo mknod -m 622 "$ROOTFS_DIR/dev/console" c 5 1
sudo mknod -m 666 "$ROOTFS_DIR/dev/null" c 1 3

# Copy installed modules
cp -r "$WORKDIR/staging/lib" "$ROOTFS_DIR/"

# === Build ext4 image ===
echo "▶ Creating rootfs.img..."
rm -f "$ROOTFS_IMG"
dd if=/dev/zero of="$ROOTFS_IMG" bs=1M count=64
mkfs.ext4 -F "$ROOTFS_IMG"

sudo umount mnt 2>/dev/null || true
rm -rf mnt
mkdir mnt

sudo mount "$ROOTFS_IMG" mnt
sudo cp -a "$ROOTFS_DIR"/. mnt/
sudo umount mnt
rmdir mnt

# === Launch QEMU ===
echo
echo "▶ Booting in QEMU (Ctrl+A then X to exit)..."
qemu-system-x86_64 \
  -kernel "$BZIMAGE" \
  -drive file="$ROOTFS_IMG",format=raw,if=virtio \
  -append "$QEMU_CMDLINE" \
  -m "$QEMU_MEM" \
  -nographic
