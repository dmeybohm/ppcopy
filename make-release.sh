#!/bin/sh
# Build a binary release of ppcopy.
#
# Bundles the DOS programs (ppread.com, ppwrite.com) with static Linux
# binaries for i386 and x86-64 into a versioned tarball and zip.
#
# Usage: ./make-release.sh [VERSION]
#   VERSION defaults to `git describe --tags --always`.
#
# Requirements: nasm, musl-tools (for -x64), and the 32-bit musl
# toolchain from ./build-musl-i386.sh (for -i386).

set -eu

cd "$(dirname "$0")"

VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo unknown)}"
NAME="ppcopy-$VERSION"
DIST="dist"
STAGE="$DIST/$NAME"

echo "Building $NAME"

make check-release-toolchain
make clean
make dos linux-i386 linux-x64

rm -rf "$STAGE"
mkdir -p "$STAGE"

# DOS binaries are already minimal; strip debug info from the Linux ones.
cp ppread.com ppwrite.com "$STAGE/"
for bin in ppread-i386 ppwrite-i386 ppread-x64 ppwrite-x64; do
    strip --strip-all -o "$STAGE/$bin" "$bin"
done

cp README.md PROTOCOL.md COPYING "$STAGE/"

(cd "$DIST" && tar czf "$NAME.tar.gz" "$NAME")
if command -v zip >/dev/null 2>&1; then
    (cd "$DIST" && rm -f "$NAME.zip" && zip -qr "$NAME.zip" "$NAME")
fi

(cd "$DIST" && sha256sum "$NAME".tar.gz "$NAME".zip 2>/dev/null > "$NAME.sha256")

echo
echo "Release contents:"
ls -l "$STAGE"
echo
echo "Archives:"
ls -l "$DIST/$NAME".*
