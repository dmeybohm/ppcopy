#!/bin/sh
# Build a 32-bit musl libc and musl-gcc wrapper for the linux-i386 target.
#
# Ubuntu's musl-tools package is x86_64 only, so for small static i386
# binaries we build musl from source against the multilib gcc. The result
# is installed under musl-i386/install in the project directory; the
# Makefile picks it up automatically for the linux-i386 target.
#
# Requirements: gcc-multilib, wget, make.
#
# The installed wrapper and specs file contain no absolute paths: the
# wrapper exports its own location and the specs file reads it from the
# environment, so the checkout can be moved freely.

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
    wget -O "$TARBALL" "$MUSL_URL"
fi

echo "$MUSL_SHA256  $TARBALL" | sha256sum -c -

rm -rf "$SRC_DIR"
tar xzf "$TARBALL" -C "$WORK_DIR"

echo "Building musl $MUSL_VERSION for i386..."
cd "$SRC_DIR"
./configure --prefix="$PREFIX" --target=i386 --disable-shared \
    CC="gcc -m32" AR=ar RANLIB=ranlib
make -j"$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
make install

# Replace musl's generated wrapper and specs file. The generated ones embed
# the absolute install prefix, and the wrapper embeds "gcc -m32" as a single
# command name that exec can't resolve. This wrapper locates itself and
# exports the prefix; the specs file pulls paths from that variable via
# %:getenv, so nothing on disk is tied to the install location. The specs
# file also adds "-m elf_i386", which musl's link spec drops when it
# replaces gcc's own, leaving the linker defaulting to x86-64.
cat > "$PREFIX/bin/musl-gcc" <<'WRAPPER'
#!/bin/sh
MUSL_I386_PREFIX=$(cd "$(dirname "$0")/.." && pwd)
export MUSL_I386_PREFIX
exec "${REALGCC:-gcc}" -m32 "$@" -specs "$MUSL_I386_PREFIX/lib/musl-gcc.specs"
WRAPPER
chmod +x "$PREFIX/bin/musl-gcc"

cat > "$PREFIX/lib/musl-gcc.specs" <<'SPECS'
%rename cpp_options old_cpp_options

*cpp_options:
-nostdinc -isystem %:getenv(MUSL_I386_PREFIX /include) -isystem include%s %(old_cpp_options)

*cc1:
%(cc1_cpu) -nostdinc -isystem %:getenv(MUSL_I386_PREFIX /include) -isystem include%s

*link_libgcc:
-L%:getenv(MUSL_I386_PREFIX /lib) -L .%s

*libgcc:
libgcc.a%s %:if-exists(libgcc_eh.a%s)

*startfile:
%{shared:;static-pie:%:getenv(MUSL_I386_PREFIX /lib/rcrt1.o); :%:getenv(MUSL_I386_PREFIX /lib/Scrt1.o)} %:getenv(MUSL_I386_PREFIX /lib/crti.o) crtbeginS.o%s

*endfile:
crtendS.o%s %:getenv(MUSL_I386_PREFIX /lib/crtn.o)

*link:
-m elf_i386 -dynamic-linker /lib/ld-musl-i386.so.1 -nostdlib %{shared:-shared} %{static:-static} %{static-pie:-static -pie --no-dynamic-linker} %{rdynamic:-export-dynamic}

*esp_link:


*esp_options:


*esp_cpp_options:


SPECS

echo
echo "Installed to $PREFIX"
echo "Wrapper: $PREFIX/bin/musl-gcc"
