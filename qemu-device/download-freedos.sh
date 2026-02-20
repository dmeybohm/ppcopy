#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGES_DIR="$SCRIPT_DIR/images"
ZIP_FILE="$IMAGES_DIR/FD14-LiveCD.zip"
ISO_FILE="$IMAGES_DIR/FD14LIVE.iso"
IMG_FILE="$IMAGES_DIR/FD14BOOT.img"
URL="https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/distributions/1.4/FD14-LiveCD.zip"

if [ -f "$ISO_FILE" ] && [ -f "$IMG_FILE" ]; then
    echo "FreeDOS images already exist, skipping download."
    exit 0
fi

mkdir -p "$IMAGES_DIR"

echo "Downloading FreeDOS 1.4 LiveCD..."
wget -O "$ZIP_FILE" "$URL"

echo "Extracting FreeDOS images..."
unzip -o -j "$ZIP_FILE" "FD14LIVE.iso" "FD14BOOT.img" -d "$IMAGES_DIR"

echo "Done. FreeDOS images extracted to $IMAGES_DIR"
