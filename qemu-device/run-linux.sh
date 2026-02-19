#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CDROM="$SCRIPT_DIR/images/alpine-virt-3.23.3-x86.iso"
FLOPPY=""
SIDE=1
STATEFILE="/tmp/laplink.state"
MEMORY=128

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Launch an Alpine Linux QEMU instance with the LapLink parallel port device."
    echo
    echo "Options:"
    echo "  -c <cdrom>      CD-ROM ISO (default: images/alpine-virt-3.23.3-x86.iso)"
    echo "  -f <floppy>     Floppy image (default: ppcopy-linux.img or ppcopy-linux2.img based on side)"
    echo "  -s <side>       LapLink cable side, 0 or 1 (default: 1)"
    echo "  -S <statefile>  Shared state file path (default: /tmp/laplink.state)"
    echo "  -m <memory>     RAM in MB (default: 128)"
    echo "  -h              Show this help"
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
        FLOPPY="$SCRIPT_DIR/images/ppcopy-linux.img"
    else
        FLOPPY="$SCRIPT_DIR/images/ppcopy-linux2.img"
    fi
fi

if [ ! -f "$STATEFILE" ]; then
    truncate -s 2 "$STATEFILE"
fi

"$SCRIPT_DIR/../qemu/build/qemu-system-i386" \
    -m "$MEMORY" \
    -boot d \
    -cdrom "$CDROM" \
    -fda "$FLOPPY" \
    -parallel none \
    -device isa-laplink,side="$SIDE",file="$STATEFILE"
