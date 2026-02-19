#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CDROM="$SCRIPT_DIR/images/FD14LIVE.iso"
FLOPPY="$SCRIPT_DIR/images/ppcopy.img"
SIDE=0
STATEFILE="/tmp/laplink.state"
MEMORY=32

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Launch a FreeDOS QEMU instance with the LapLink parallel port device."
    echo
    echo "Options:"
    echo "  -c <cdrom>      CD-ROM ISO (default: images/FD14LIVE.iso)"
    echo "  -f <floppy>     Floppy image (default: images/ppcopy.img)"
    echo "  -s <side>       LapLink cable side, 0 or 1 (default: 0)"
    echo "  -S <statefile>  Shared state file path (default: /tmp/laplink.state)"
    echo "  -m <memory>     RAM in MB (default: 32)"
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

if [ ! -f "$STATEFILE" ]; then
    truncate -s 2 "$STATEFILE"
fi

qemu-system-i386 \
    -m "$MEMORY" \
    -boot d \
    -cdrom "$CDROM" \
    -fda "$FLOPPY" \
    -parallel none \
    -device isa-laplink,side="$SIDE",statefile="$STATEFILE"
