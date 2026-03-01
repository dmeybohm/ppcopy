#!/bin/bash
#
# run-tests.sh — Automated integration tests for ppcopy
#
# Runs all 4 transfer combinations (DOS→Linux, Linux→DOS, DOS→DOS, Linux→Linux)
# using QEMU with the isa-laplink device.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
QEMU="${QEMU:-$PROJECT_DIR/qemu/install/bin/qemu-system-i386}"
IMAGES_DIR="$PROJECT_DIR/qemu-device/images"
FREEDOS_IMG="$IMAGES_DIR/FD14BOOT.img"
ALPINE_ISO="$IMAGES_DIR/alpine-virt-3.23.3-x86.iso"
TESTDATA="$SCRIPT_DIR/testdata.txt"
LINUX_INIT="$SCRIPT_DIR/linux-test-init.sh"
TMP_DIR="$SCRIPT_DIR/tmp"
TIMEOUT=90

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ─── Cleanup ────────────────────────────────────────────────────────────────

cleanup() {
    # Kill any leftover QEMU processes we started
    for pid in "${QEMU_PIDS[@]:-}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT
QEMU_PIDS=()

# ─── Prerequisites ──────────────────────────────────────────────────────────

check_prerequisites() {
    local missing=()

    if [ ! -x "$QEMU" ]; then
        missing+=("qemu-system-i386 (run 'make download-qemu')")
    fi
    if [ ! -f "$FREEDOS_IMG" ]; then
        missing+=("FD14BOOT.img (run 'make download-freedos')")
    fi
    if [ ! -f "$ALPINE_ISO" ]; then
        missing+=("Alpine ISO (run 'make download-alpine')")
    fi

    for tool in mcopy mformat mdel isoinfo cpio gzip md5sum; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Missing prerequisites:"
        for m in "${missing[@]}"; do
            echo "  - $m"
        done
        exit 1
    fi
}

# ─── Alpine kernel/initramfs extraction ─────────────────────────────────────

extract_alpine_kernel() {
    local cache_dir="$TMP_DIR/alpine"
    if [ -f "$cache_dir/vmlinuz-virt" ] && [ -f "$cache_dir/initramfs-virt" ]; then
        return 0
    fi
    mkdir -p "$cache_dir"
    echo "  Extracting Alpine kernel and initramfs from ISO..."
    isoinfo -R -x /boot/vmlinuz-virt -i "$ALPINE_ISO" > "$cache_dir/vmlinuz-virt"
    isoinfo -R -x /boot/initramfs-virt -i "$ALPINE_ISO" > "$cache_dir/initramfs-virt"
    if [ ! -s "$cache_dir/vmlinuz-virt" ] || [ ! -s "$cache_dir/initramfs-virt" ]; then
        echo "ERROR: Failed to extract kernel/initramfs from Alpine ISO"
        exit 1
    fi
}

# ─── DOS floppy preparation ─────────────────────────────────────────────────

prepare_dos_boot_floppy() {
    local floppy="$1"
    local test_command="$2"

    cp "$FREEDOS_IMG" "$floppy"
    # Delete existing FDAUTO.BAT and replace with our test script
    mdel -i "$floppy" ::FDAUTO.BAT 2>/dev/null || true
    # Write new FDAUTO.BAT: run the test command, then power off
    local tmpbat="$TMP_DIR/FDAUTO.BAT"
    printf '%s\r\n%s\r\n' "$test_command" '\FREEDOS\BIN\FDAPM POWEROFF' > "$tmpbat"
    mcopy -i "$floppy" "$tmpbat" ::FDAUTO.BAT
}

# ─── DOS auxiliary HDD preparation ──────────────────────────────────────────

prepare_dos_hdd() {
    local hdd="$1"
    shift
    # Files to copy are passed as remaining args (source:dest pairs)

    # Create a 2MB FAT hard disk image
    dd if=/dev/zero of="$hdd" bs=512 count=4096 2>/dev/null
    mformat -i "$hdd" -h 4 -s 32 -t 64 ::

    while [ $# -gt 0 ]; do
        local src="${1%%:*}"
        local dst="${1##*:}"
        mcopy -i "$hdd" "$src" "::$dst"
        shift
    done
}

# ─── Linux initramfs overlay ────────────────────────────────────────────────

prepare_linux_initrd() {
    local combined="$1"
    local role="$2"  # writer or reader

    local overlay_dir="$TMP_DIR/overlay-$$-$role"
    mkdir -p "$overlay_dir"

    # Copy stripped binaries
    cp "$PROJECT_DIR/ppread-i386" "$overlay_dir/ppread-i386"
    cp "$PROJECT_DIR/ppwrite-i386" "$overlay_dir/ppwrite-i386"
    strip --strip-all "$overlay_dir/ppread-i386" "$overlay_dir/ppwrite-i386"
    chmod +x "$overlay_dir/ppread-i386" "$overlay_dir/ppwrite-i386"

    # Copy test data and init script
    cp "$TESTDATA" "$overlay_dir/testdata.txt"
    cp "$LINUX_INIT" "$overlay_dir/init"
    chmod +x "$overlay_dir/init"

    # Build overlay cpio archive
    local overlay_cpio="$TMP_DIR/overlay-$$-$role.cpio.gz"
    (cd "$overlay_dir" && find . | cpio -o -H newc 2>/dev/null | gzip) > "$overlay_cpio"

    # Concatenate Alpine initramfs + overlay
    cat "$TMP_DIR/alpine/initramfs-virt" "$overlay_cpio" > "$combined"

    rm -rf "$overlay_dir"
}

# ─── Run a single test ──────────────────────────────────────────────────────

# launch_dos_vm SIDE STATE_FILE BOOT_FLOPPY AUX_HDD
launch_dos_vm() {
    local side="$1" state="$2" floppy="$3" hdd="$4"
    "$QEMU" -m 32 -boot a \
        -drive file="$floppy",format=raw,if=floppy \
        -drive file="$hdd",format=raw \
        -display none -no-reboot -parallel none \
        -device isa-laplink,side="$side",file="$state" 2>/dev/null &
    QEMU_PIDS+=($!)
}

# launch_linux_vm SIDE STATE_FILE VMLINUZ INITRD ROLE LOG_FILE
launch_linux_vm() {
    local side="$1" state="$2" vmlinuz="$3" initrd="$4" role="$5" log="$6"
    "$QEMU" -m 128 -kernel "$vmlinuz" -initrd "$initrd" \
        -append "console=ttyS0 init=/init ppcopy_role=$role ppcopy_file=/testdata.txt" \
        -display none -serial file:"$log" -no-reboot \
        -parallel none -device isa-laplink,side="$side",file="$state" 2>/dev/null &
    QEMU_PIDS+=($!)
}

wait_with_timeout() {
    local pid1="$1" pid2="$2" timeout="$3"
    local elapsed=0

    while [ "$elapsed" -lt "$timeout" ]; do
        local alive=0
        kill -0 "$pid1" 2>/dev/null && alive=$((alive + 1))
        kill -0 "$pid2" 2>/dev/null && alive=$((alive + 1))
        if [ "$alive" -eq 0 ]; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    # Timeout — kill remaining processes
    kill "$pid1" 2>/dev/null || true
    kill "$pid2" 2>/dev/null || true
    wait "$pid1" 2>/dev/null || true
    wait "$pid2" 2>/dev/null || true
    return 1
}

# ─── Test scenarios ─────────────────────────────────────────────────────────

# Test 1: DOS writer → Linux reader
test_dos_to_linux() {
    local test_dir="$TMP_DIR/test1"
    mkdir -p "$test_dir"

    local state="$test_dir/laplink.state"
    truncate -s 2 "$state"

    # Prepare DOS writer: floppy boots, runs PPWRITE.COM C:\TESTDATA.TXT
    local floppy="$test_dir/boot.img"
    prepare_dos_boot_floppy "$floppy" "C:\PPWRITE.COM C:\TESTDATA.TXT"

    local hdd="$test_dir/hdd.img"
    prepare_dos_hdd "$hdd" \
        "$PROJECT_DIR/ppwrite.com:PPWRITE.COM" \
        "$TESTDATA:TESTDATA.TXT"

    # Prepare Linux reader
    local initrd="$test_dir/initrd.img"
    prepare_linux_initrd "$initrd" "reader"

    local log="$test_dir/serial.log"

    # Launch VMs
    local vmlinuz="$TMP_DIR/alpine/vmlinuz-virt"
    launch_linux_vm 1 "$state" "$vmlinuz" "$initrd" "reader" "$log"
    local linux_pid=${QEMU_PIDS[-1]}
    launch_dos_vm 0 "$state" "$floppy" "$hdd"
    local dos_pid=${QEMU_PIDS[-1]}

    if ! wait_with_timeout "$linux_pid" "$dos_pid" "$TIMEOUT"; then
        echo "FAIL (timeout)"
        return 1
    fi

    # Verify
    if grep -q "PPCOPY_TEST_PASSED" "$log" 2>/dev/null; then
        echo "PASS"
        return 0
    else
        echo "FAIL"
        if [ -f "$log" ]; then
            echo "  Serial log: $(cat "$log")"
        fi
        return 1
    fi
}

# Test 2: Linux writer → DOS reader
test_linux_to_dos() {
    local test_dir="$TMP_DIR/test2"
    mkdir -p "$test_dir"

    local state="$test_dir/laplink.state"
    truncate -s 2 "$state"

    # Prepare Linux writer
    local initrd="$test_dir/initrd.img"
    prepare_linux_initrd "$initrd" "writer"

    # Prepare DOS reader: floppy boots, runs PPREAD.COM (writes to C:\PPREAD.OUT)
    local floppy="$test_dir/boot.img"
    prepare_dos_boot_floppy "$floppy" "C:\PPREAD.COM"

    local hdd="$test_dir/hdd.img"
    prepare_dos_hdd "$hdd" \
        "$PROJECT_DIR/ppread.com:PPREAD.COM"

    local log="$test_dir/serial.log"

    # Launch VMs
    local vmlinuz="$TMP_DIR/alpine/vmlinuz-virt"
    launch_dos_vm 1 "$state" "$floppy" "$hdd"
    local dos_pid=${QEMU_PIDS[-1]}
    launch_linux_vm 0 "$state" "$vmlinuz" "$initrd" "writer" "$log"
    local linux_pid=${QEMU_PIDS[-1]}

    if ! wait_with_timeout "$linux_pid" "$dos_pid" "$TIMEOUT"; then
        echo "FAIL (timeout)"
        return 1
    fi

    # Extract PPREAD.OUT from HDD and compare
    local received="$test_dir/received.bin"
    if mcopy -i "$hdd" ::PPREAD.OUT "$received" 2>/dev/null; then
        if cmp -s "$TESTDATA" "$received"; then
            echo "PASS"
            return 0
        else
            echo "FAIL (data mismatch)"
            return 1
        fi
    else
        echo "FAIL (PPREAD.OUT not found on HDD)"
        return 1
    fi
}

# Test 3: DOS writer → DOS reader
test_dos_to_dos() {
    local test_dir="$TMP_DIR/test3"
    mkdir -p "$test_dir"

    local state="$test_dir/laplink.state"
    truncate -s 2 "$state"

    # Prepare DOS writer
    local writer_floppy="$test_dir/writer-boot.img"
    prepare_dos_boot_floppy "$writer_floppy" "C:\PPWRITE.COM C:\TESTDATA.TXT"

    local writer_hdd="$test_dir/writer-hdd.img"
    prepare_dos_hdd "$writer_hdd" \
        "$PROJECT_DIR/ppwrite.com:PPWRITE.COM" \
        "$TESTDATA:TESTDATA.TXT"

    # Prepare DOS reader
    local reader_floppy="$test_dir/reader-boot.img"
    prepare_dos_boot_floppy "$reader_floppy" "C:\PPREAD.COM"

    local reader_hdd="$test_dir/reader-hdd.img"
    prepare_dos_hdd "$reader_hdd" \
        "$PROJECT_DIR/ppread.com:PPREAD.COM"

    # Launch VMs
    launch_dos_vm 0 "$state" "$writer_floppy" "$writer_hdd"
    local writer_pid=${QEMU_PIDS[-1]}
    launch_dos_vm 1 "$state" "$reader_floppy" "$reader_hdd"
    local reader_pid=${QEMU_PIDS[-1]}

    if ! wait_with_timeout "$writer_pid" "$reader_pid" "$TIMEOUT"; then
        echo "FAIL (timeout)"
        return 1
    fi

    # Extract PPREAD.OUT from reader HDD and compare
    local received="$test_dir/received.bin"
    if mcopy -i "$reader_hdd" ::PPREAD.OUT "$received" 2>/dev/null; then
        if cmp -s "$TESTDATA" "$received"; then
            echo "PASS"
            return 0
        else
            echo "FAIL (data mismatch)"
            return 1
        fi
    else
        echo "FAIL (PPREAD.OUT not found on reader HDD)"
        return 1
    fi
}

# Test 4: Linux writer → Linux reader
test_linux_to_linux() {
    local test_dir="$TMP_DIR/test4"
    mkdir -p "$test_dir"

    local state="$test_dir/laplink.state"
    truncate -s 2 "$state"

    # Prepare both Linux VMs
    local writer_initrd="$test_dir/writer-initrd.img"
    prepare_linux_initrd "$writer_initrd" "writer"

    local reader_initrd="$test_dir/reader-initrd.img"
    prepare_linux_initrd "$reader_initrd" "reader"

    local vmlinuz="$TMP_DIR/alpine/vmlinuz-virt"
    local writer_log="$test_dir/writer-serial.log"
    local reader_log="$test_dir/reader-serial.log"

    # Launch VMs
    launch_linux_vm 0 "$state" "$vmlinuz" "$writer_initrd" "writer" "$writer_log"
    local writer_pid=${QEMU_PIDS[-1]}
    launch_linux_vm 1 "$state" "$vmlinuz" "$reader_initrd" "reader" "$reader_log"
    local reader_pid=${QEMU_PIDS[-1]}

    if ! wait_with_timeout "$writer_pid" "$reader_pid" "$TIMEOUT"; then
        echo "FAIL (timeout)"
        return 1
    fi

    # Verify
    if grep -q "PPCOPY_TEST_PASSED" "$reader_log" 2>/dev/null; then
        echo "PASS"
        return 0
    else
        echo "FAIL"
        if [ -f "$reader_log" ]; then
            echo "  Reader log: $(cat "$reader_log")"
        fi
        if [ -f "$writer_log" ]; then
            echo "  Writer log: $(cat "$writer_log")"
        fi
        return 1
    fi
}

# ─── Main ───────────────────────────────────────────────────────────────────

echo "ppcopy integration tests"
echo "========================"

check_prerequisites

# Build binaries
echo "Building binaries..."
make -C "$PROJECT_DIR" dos linux-i386

# Create temp directory
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Extract Alpine kernel/initramfs (cached)
extract_alpine_kernel

# Run tests
run_test() {
    local num="$1" label="$2" func="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "[%d/4] %-16s ... " "$num" "$label"
    if result=$("$func" 2>&1); then
        echo "$result"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "$result"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    # Reset QEMU_PIDS for next test
    QEMU_PIDS=()
}

run_test 1 "DOS → Linux"   test_dos_to_linux
run_test 2 "Linux → DOS"   test_linux_to_dos
run_test 3 "DOS → DOS"     test_dos_to_dos
run_test 4 "Linux → Linux" test_linux_to_linux

echo ""
if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "All $TESTS_PASSED tests passed."
    exit 0
else
    echo "$TESTS_FAILED of $TESTS_RUN tests failed."
    exit 1
fi
