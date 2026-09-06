#!/bin/sh
# Build a 32-bit musl libc and musl-gcc wrapper for the linux-i386 target.
#
# Ubuntu's musl-tools package is x86_64 only, so for small static i386
# binaries we build musl from source against the multilib gcc. The result
# is installed under musl-i386/install in the project directory; the
# Makefile picks it up automatically for the linux-i386 target.
#
# Requirements: gcc-multilib, curl, make.

set -eu

MUSL_VERSION="1.2.6"
MUSL_SHA256="d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a"
MUSL_URL="https://musl.libc.org/releases/musl-$MUSL_VERSION.tar.gz"

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"
WORK_DIR="$PROJECT_DIR/musl-i386"
PREFIX="$WORK_DIR/install"
TARBALL="$WORK_DIR/musl-$MUSL_VERSION.tar.gz"
SRC_DIR="$WORK_DIR/musl-$MUSL_VERSION"

if [ -x "$PREFIX/bin/musl-gcc" ]; then
    echo "musl i386 toolchain already built at $PREFIX, skipping."
    echo "Remove $WORK_DIR to rebuild."
    exit 0
fi

mkdir -p "$WORK_DIR"

if [ ! -f "$TARBALL" ]; then
    echo "Downloading musl $MUSL_VERSION..."
    curl -fSL -o "$TARBALL" "$MUSL_URL"
fi

echo "$MUSL_SHA256  $TARBALL" | sha256sum -c -

rm -rf "$SRC_DIR"
tar xzf "$TARBALL" -C "$WORK_DIR"

echo "Building musl $MUSL_VERSION for i386..."
cd "$SRC_DIR"
./configure --prefix="$PREFIX" --target=i386 --disable-shared \
    CC="gcc -m32" AR=ar RANLIB=ranlib
make -j"$(nproc)"
make install

# musl's specs file replaces gcc's link spec, losing the "-m elf_i386" that
# -m32 would normally add, so the linker would default to x86-64. Put it back.
sed -i 's|^\*link:$|&\n-m elf_i386|' "$PREFIX/lib/musl-gcc.specs"
sed -i '/^\*link:$/{n;N;s|\n| |}' "$PREFIX/lib/musl-gcc.specs"

# musl's generated wrapper embeds "gcc -m32" as a single command name, which
# exec can't resolve. Replace it with one that passes -m32 as an argument.
cat > "$PREFIX/bin/musl-gcc" <<WRAPPER
#!/bin/sh
exec "\${REALGCC:-gcc}" -m32 "\$@" -specs "$PREFIX/lib/musl-gcc.specs"
WRAPPER
chmod +x "$PREFIX/bin/musl-gcc"

echo
echo "Installed to $PREFIX"
echo "Wrapper: $PREFIX/bin/musl-gcc"
