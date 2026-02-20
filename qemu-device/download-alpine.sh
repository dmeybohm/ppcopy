#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGES_DIR="$SCRIPT_DIR/images"
ISO_FILE="$IMAGES_DIR/alpine-virt-3.23.3-x86.iso"
URL="https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86/alpine-virt-3.23.3-x86.iso"

if [ -f "$ISO_FILE" ]; then
    echo "Alpine Linux image already exists, skipping download."
    exit 0
fi

mkdir -p "$IMAGES_DIR"

echo "Downloading Alpine Linux 3.23.3 x86..."
wget -O "$ISO_FILE" "$URL"

echo "Done. Alpine Linux image downloaded to $IMAGES_DIR"
