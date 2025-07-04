#!/bin/bash
set -e

# === CONFIGURATION ===
ARCH=x86_64
KERNEL_BZIMAGE=android-kernel/arch/x86/boot/bzImage
BUSYBOX_URL="https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64"
BUSYBOX_BIN=busybox-x86_64
INITRAMFS_DIR=initramfs
INITRAMFS_OUT=initramfs.cpio.gz

# === DOWNLOAD BUSYBOX ===
if [ ! -f "$BUSYBOX_BIN" ]; then
    echo "[+] Downloading busybox..."
    wget -q "$BUSYBOX_URL" -O "$BUSYBOX_BIN"
    chmod +x "$BUSYBOX_BIN"
fi

# === CREATE INITRAMFS STRUCTURE ===
echo "[+] Creating initramfs..."
rm -rf "$INITRAMFS_DIR"
mkdir -p "$INITRAMFS_DIR"/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev}

# === CREATE DEVICE NODES ===
echo "[+] Creating device nodes..."
sudo mknod -m 622 "$INITRAMFS_DIR/dev/console" c 5 1
sudo mknod -m 666 "$INITRAMFS_DIR/dev/null" c 1 3

# === COPY BUSYBOX ===
cp "$BUSYBOX_BIN" "$INITRAMFS_DIR/bin/busybox"
chmod +x "$INITRAMFS_DIR/bin/busybox"

# Symlink sh manually (for init)
ln -sf busybox "$INITRAMFS_DIR/bin/sh"

# Symlink all busybox applets automatically
echo "[+] Installing busybox applets..."
sudo chroot "$INITRAMFS_DIR" /bin/busybox --install -s


# === CREATE INIT SCRIPT ===
echo "[+] Creating init script..."
cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sys /sys
echo "[+] Booted successfully."
exec /bin/sh
EOF
chmod +x "$INITRAMFS_DIR/init"

# === PACK INITRAMFS ===
echo "[+] Packing initramfs..."
cd "$INITRAMFS_DIR"
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../"$INITRAMFS_OUT"
cd ..

# === CHECK CONTENTS ===
echo "[+] Checking archive content..."
zcat "$INITRAMFS_OUT" | cpio -t | grep -E '^init$|/bin/busybox$|/bin/sh$'

# === RUN QEMU ===
echo "[+] Launching QEMU..."
qemu-system-x86_64 \
    -kernel "$KERNEL_BZIMAGE" \
    -initrd "$INITRAMFS_OUT" \
    -append "console=ttyS0 init=/init" \
    -nographic \
    -cpu kvm64 \
    -m 512M \
    -no-reboot
