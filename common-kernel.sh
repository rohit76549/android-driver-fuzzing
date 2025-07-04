#!/bin/bash
set -e

echo "=== Android Kernel Build with KASAN/KCOV ==="

KERNEL_DIR="$PWD/android-kernel"
CLANG_VERSION="clang-r522817"
TOOLCHAIN_DIR="$KERNEL_DIR/prebuilts/clang/host/linux-x86/linux-x86/$CLANG_VERSION"

# ✅ Step 1: Kernel source check
if [ ! -d "$KERNEL_DIR" ]; then
    echo "[*] Cloning Android 12 common kernel (5.10)..."
    git clone https://android.googlesource.com/kernel/common android-kernel
    cd android-kernel
    git checkout origin/android12-5.10 -b android12-5.10
    echo "[*] Initializing and syncing submodules..."
    repo init -u https://android.googlesource.com/kernel/manifest -b common-android12-5.10
    repo sync -j$(nproc)
else
    echo "[*] Kernel exists, skipping clone."
    cd "$KERNEL_DIR"
fi

# ✅ Step 2: Toolchain check
if [ ! -d "$TOOLCHAIN_DIR" ]; then
    echo "❌ Toolchain not found: $TOOLCHAIN_DIR"
    echo "➡️  Please run: cd android-kernel && repo sync"
    exit 1
fi

# ✅ Step 3: Cleanup previous build
echo "[*] Cleaning previous builds..."
make ARCH=x86_64 distclean

# ✅ Step 4: Kernel config with KASAN/KCOV
echo "[*] Setting up kernel config for KASAN/KCOV..."
make ARCH=x86_64 defconfig
scripts/config --enable CONFIG_KASAN \
               --enable CONFIG_KCOV \
               --disable CONFIG_STACK_VALIDATION \
               --enable CONFIG_DEBUG_INFO \
               --enable CONFIG_DEBUG_KERNEL \
               --enable CONFIG_DEBUG_MISC \
               --enable CONFIG_DEBUG_FS \
               --enable CONFIG_DEBUG_INFO_DWARF4 \
               --set-val CONFIG_FRAME_WARN 2048

make ARCH=x86_64 olddefconfig

✅ Step 5: Build
echo "[*] Building kernel..."
make -j$(nproc) \
  ARCH=x86_64 \
  CC="$TOOLCHAIN_DIR/bin/clang" \
  LLVM=1 \
  LLVM_IAS=1

echo "✅ Build complete!"

# #!/bin/bash
# set -e

# echo "=== Android Kernel Build with KASAN/KCOV (Frame Warn Adjusted) ==="

# KERNEL_DIR="$PWD/android-kernel"
# CLANG_VERSION="clang-r522817"
# TOOLCHAIN_DIR="$KERNEL_DIR/prebuilts/clang/host/linux-x86/linux-x86/$CLANG_VERSION"

# cd "$KERNEL_DIR"

# # Step 1: Clean
# make ARCH=x86_64 distclean

# # Step 2: Base config & enable KASAN/KCOV
# make ARCH=x86_64 defconfig
# scripts/config --enable CONFIG_KASAN \
#                --enable CONFIG_KCOV \
#                --disable CONFIG_STACK_VALIDATION \
#                --enable CONFIG_DEBUG_INFO \
#                --enable CONFIG_DEBUG_KERNEL \
#                --enable CONFIG_DEBUG_MISC \
#                --enable CONFIG_DEBUG_FS \
#                --enable CONFIG_DEBUG_INFO_DWARF4 \
#                --set-val CONFIG_FRAME_WARN 4096  # ← increased threshold

# make ARCH=x86_64 olddefconfig

# # Step 3: Build
# make -j$(nproc) \
#      ARCH=x86_64 \
#      CC="$TOOLCHAIN_DIR/bin/clang" \
#      LLVM=1 LLVM_IAS=1

# echo "✅ Build complete!"
