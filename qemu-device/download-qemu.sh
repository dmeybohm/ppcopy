#!/bin/bash
#
# Clone a pinned QEMU commit, add the LapLink device, and build only the
# i386 system emulator into qemu/install.
#
# Requirements: git, python3, ninja, pkg-config, glib and pixman development
# headers (Debian/Ubuntu: ninja-build libglib2.0-dev libpixman-1-dev).
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QEMU_DIR="$SCRIPT_DIR/../qemu"
INSTALL_DIR="$QEMU_DIR/install"
QEMU_COMMIT="07f97d5da04a9f97e273de85c76f5017d8135a6e"

if [ -x "$INSTALL_DIR/bin/qemu-system-i386" ]; then
    echo "QEMU already installed, skipping. Remove qemu/ to rebuild."
    exit 0
fi

echo "Cloning QEMU at $QEMU_COMMIT..."
rm -rf "$QEMU_DIR"
git init "$QEMU_DIR"
cd "$QEMU_DIR"
git remote add origin https://gitlab.com/qemu-project/qemu.git
git fetch --depth 1 origin "$QEMU_COMMIT"
git checkout FETCH_HEAD

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

echo "Configuring QEMU (i386-softmmu only, minimal features)..."
mkdir -p "$QEMU_DIR/build"
cd "$QEMU_DIR/build"
../configure --target-list=i386-softmmu \
    --prefix=/usr/local \
    --without-default-features \
    --enable-tcg

echo "Building QEMU..."
ninja

echo "Installing QEMU to $INSTALL_DIR..."
DESTDIR="$INSTALL_DIR" ninja install

# Keep only the binary and firmware files actually needed by the tests.
# The full DESTDIR install is under install/usr/local/; move to install/{bin,share}.
mv "$INSTALL_DIR/usr/local/bin" "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/share/qemu"
for f in bios-256k.bin kvmvapic.bin linuxboot_dma.bin vgabios-stdvga.bin efi-e1000.rom; do
    mv "$INSTALL_DIR/usr/local/share/qemu/$f" "$INSTALL_DIR/share/qemu/"
done
rm -rf "$INSTALL_DIR/usr"

echo "Done. QEMU installed at $INSTALL_DIR/bin/qemu-system-i386"
