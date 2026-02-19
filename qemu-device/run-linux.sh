#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CDROM="$SCRIPT_DIR/images/alpine-virt-3.23.3-x86.iso"
DISK="$SCRIPT_DIR/images/ppcopy-linux.img"
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
    echo "  -d <disk>       Extra FAT disk image (default: images/ppcopy-linux.img)"
    echo "  -s <side>       LapLink cable side, 0 or 1 (default: 1)"
    echo "  -S <statefile>  Shared state file path (default: /tmp/laplink.state)"
    echo "  -m <memory>     RAM in MB (default: 128)"
    echo "  -h              Show this help"
}

while getopts "c:d:s:S:m:h" opt; do
    case "$opt" in
        c) CDROM="$OPTARG" ;;
        d) DISK="$OPTARG" ;;
        s) SIDE="$OPTARG" ;;
        S) STATEFILE="$OPTARG" ;;
        m) MEMORY="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

if [ ! -f "$STATEFILE" ]; then
    truncate -s 2 "$STATEFILE"
fi

"$SCRIPT_DIR/../qemu/build/qemu-system-i386" \
    -m "$MEMORY" \
    -boot d \
    -cdrom "$CDROM" \
    -drive file="$DISK",format=raw,if=ide \
    -parallel none \
    -device isa-laplink,side="$SIDE",statefile="$STATEFILE"
