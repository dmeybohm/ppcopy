#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QEMU_DIR="$SCRIPT_DIR/../qemu"

if [ -d "$QEMU_DIR/build" ] && [ -x "$QEMU_DIR/build/qemu-system-i386" ]; then
    echo "QEMU already built, skipping. Remove qemu/ to rebuild."
    exit 0
fi

echo "Cloning QEMU..."
git clone https://gitlab.com/qemu-project/qemu.git --depth 10 "$QEMU_DIR"

echo "Installing LapLink device..."
cp "$SCRIPT_DIR/laplink.c" "$QEMU_DIR/hw/char/laplink.c"
cp "$SCRIPT_DIR/laplink.h" "$QEMU_DIR/include/hw/char/laplink.h"

# Fix include path for QEMU source tree layout
sed -i 's|#include "laplink.h"|#include "hw/char/laplink.h"|' "$QEMU_DIR/hw/char/laplink.c"

# Add Kconfig entry
cat >> "$QEMU_DIR/hw/char/Kconfig" <<'EOF'

config LAPLINK
    bool
    default y
    depends on ISA_BUS
EOF

# Add to meson build
sed -i "/system_ss.add(when: 'CONFIG_GOLDFISH_TTY'/a system_ss.add(when: 'CONFIG_LAPLINK', if_true: files('laplink.c'))" \
    "$QEMU_DIR/hw/char/meson.build"

echo "Configuring QEMU (i386-softmmu only)..."
mkdir -p "$QEMU_DIR/build"
cd "$QEMU_DIR/build"
../configure --target-list=i386-softmmu

echo "Building QEMU..."
ninja

echo "Done. QEMU built at $QEMU_DIR/build/qemu-system-i386"
