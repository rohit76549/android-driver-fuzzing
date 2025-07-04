#!/bin/bash
set -euo pipefail

# === CONFIG ===
KERNEL_BZIMAGE="android-kernel/arch/x86/boot/bzImage"
BUSYBOX_URL="https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64"
BUSYBOX_BIN="busybox-x86_64"
ROOTFS_DIR="rootfs-tmp"
ROOTFS_IMG="rootfs.img"
IMG_SIZE_MB=64

# 1) Download static BusyBox if needed
if [ ! -x "$BUSYBOX_BIN" ]; then
  echo "[*] Downloading BusyBox..."
  wget -q "$BUSYBOX_URL" -O "$BUSYBOX_BIN"
  chmod +x "$BUSYBOX_BIN"
fi

# 2) Build the rootfs tree
echo "[*] Setting up $ROOTFS_DIR/"
rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev,root,tmp}

# 3) Create device nodes
echo "[*] Creating device nodes..."
sudo mknod -m 622 "$ROOTFS_DIR/dev/console" c 5 1
sudo mknod -m 666 "$ROOTFS_DIR/dev/null"   c 1 3

# 4) Install BusyBox and all its applets
echo "[*] Installing BusyBox and applets..."
cp "$BUSYBOX_BIN" "$ROOTFS_DIR/bin/busybox"
chmod +x "$ROOTFS_DIR/bin/busybox"
pushd "$ROOTFS_DIR/bin" > /dev/null
for applet in $(./busybox --list); do
  ln -sf busybox "$applet"
done
popd  > /dev/null

# 5) Create /init
cat > "$ROOTFS_DIR/init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
echo
echo "[+] Rootfs mounted. Dropping to shell..."
exec /bin/sh
EOF
chmod +x "$ROOTFS_DIR/init"

# 6) Make an ext4 image and populate it
echo "[*] Creating $ROOTFS_IMG (${IMG_SIZE_MB}MiB ext4)…"
dd if=/dev/zero of="$ROOTFS_IMG" bs=1M count="$IMG_SIZE_MB" status=none
mkfs.ext4 -q "$ROOTFS_IMG"

echo "[*] Populating image…"
mkdir -p mnt
sudo mount -o loop "$ROOTFS_IMG" mnt
sudo cp -a "$ROOTFS_DIR/." mnt/
sudo umount mnt
rmdir mnt

# 7) Launch QEMU
echo "[*] Booting QEMU…"
qemu-system-x86_64 \
  -kernel "$KERNEL_BZIMAGE" \
  -drive file="$ROOTFS_IMG",format=raw,if=virtio \
  -append "console=ttyS0 root=/dev/vda rw init=/init nokaslr selinux=0 quiet" \
  -m 1024M \
  -nographic

# 8) Cleanup
sudo rm -f "$ROOTFS_DIR/dev/console" "$ROOTFS_DIR/dev/null"
echo "[+] QEMU exited."
