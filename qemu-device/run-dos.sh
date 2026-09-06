#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QEMU="${QEMU:-$SCRIPT_DIR/../qemu/install/bin/qemu-system-i386}"

CDROM="$SCRIPT_DIR/images/FD14LIVE.iso"
FLOPPY=""
SIDE=0
STATEFILE="${TMPDIR:-/tmp}/laplink.state"
MEMORY=32

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Launch a FreeDOS QEMU instance with the LapLink parallel port device."
    echo
    echo "Options:"
    echo "  -c <cdrom>      CD-ROM ISO (default: images/FD14LIVE.iso)"
    echo "  -f <floppy>     Floppy image (default: ppcopy-dos.img or ppcopy-dos2.img based on side)"
    echo "  -s <side>       LapLink cable side, 0 or 1 (default: 0)"
    echo "  -S <statefile>  Shared state file path (default: \$TMPDIR/laplink.state)"
    echo "  -m <memory>     RAM in MB (default: 32)"
    echo "  -h              Show this help"
    echo
    echo "Set QEMU to override the qemu-system-i386 binary (default: qemu/install/bin)."
}

while getopts "c:f:s:S:m:h" opt; do
    case "$opt" in
        c) CDROM="$OPTARG" ;;
        f) FLOPPY="$OPTARG" ;;
        s) SIDE="$OPTARG" ;;
        S) STATEFILE="$OPTARG" ;;
        m) MEMORY="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

if [ -z "$FLOPPY" ]; then
    if [ "$SIDE" -eq 0 ]; then
        FLOPPY="$SCRIPT_DIR/images/ppcopy-dos.img"
    else
        FLOPPY="$SCRIPT_DIR/images/ppcopy-dos2.img"
    fi
fi

if [ ! -f "$STATEFILE" ]; then
    truncate -s 2 "$STATEFILE"
fi

"$QEMU" \
    -m "$MEMORY" \
    -boot d \
    -cdrom "$CDROM" \
    -fda "$FLOPPY" \
    -parallel none \
    -device isa-laplink,side="$SIDE",file="$STATEFILE"
