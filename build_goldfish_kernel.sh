#!/bin/bash
set -e

# Create goldfish directory if missing
if [ ! -d "goldfish" ]; then
  git clone https://android.googlesource.com/kernel/goldfish
fi

cd goldfish

# Clean previous build artifacts
make clean || true
make mrproper || true

# Ensure correct branch
BRANCH="android-goldfish-4.14-dev"
if git rev-parse --verify $BRANCH >/dev/null 2>&1; then
  git checkout $BRANCH
  git pull origin $BRANCH
else
  git fetch origin $BRANCH
  git checkout -b $BRANCH origin/$BRANCH
fi

# Configure for x86_64 QEMU
make ARCH=x86_64 x86_64_ranchu_defconfig

# Enable fuzzing features
scripts/config --enable KCOV
scripts/config --enable KCOV_ENABLE_COMPARISONS
scripts/config --enable KASAN
scripts/config --enable KASAN_INLINE
scripts/config --enable DEBUG_KERNEL
scripts/config --enable DEBUG_FS

# Disable problematic GCC plugins
scripts/config --disable GCC_PLUGINS
scripts/config --disable GCC_PLUGIN_CYC_COMPLEXITY
scripts/config --disable GCC_PLUGIN_SANCOV
scripts/config --disable GCC_PLUGIN_LATENT_ENTROPY
scripts/config --disable GCC_PLUGIN_STRUCTLEAK
scripts/config --disable GCC_PLUGIN_STRUCTLEAK_BYREF_ALL
scripts/config --disable GCC_PLUGIN_STRUCTLEAK_VERBOSE
scripts/config --disable GCC_PLUGIN_RANDSTRUCT
scripts/config --disable GCC_PLUGIN_RANDSTRUCT_PERFORMANCE

# Apply configuration changes
yes "" | make ARCH=x86_64 olddefconfig

# Build kernel with verbose output
make -j$(nproc) ARCH=x86_64 V=1

# Verification
echo "Build verification:"
grep "CONFIG_KCOV=y" .config || (echo "KCOV not enabled!"; exit 1)
grep "CONFIG_KASAN=y" .config || (echo "KASAN not enabled!"; exit 1)
echo "Kernel built successfully at arch/x86_64/boot/bzImage"
