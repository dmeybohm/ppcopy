#!/bin/sh
#
# linux-test-init.sh — Init script for Linux test VMs
#
# Runs as PID 1 inside Alpine-based QEMU VM.
# Parameterized via kernel command line:
#   ppcopy_role=writer  — runs ppwrite-i386
#   ppcopy_role=reader  — runs ppread-i386, verifies md5, reports PASS/FAIL
#   ppcopy_file=/testdata.txt — file to send (writer) or expected file (reader)
#

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# Alpine's initramfs only has busybox + sh; create symlinks for all applets
/usr/bin/busybox --install -s

mount -t proc none /proc
mount -t devtmpfs none /dev

# Parse kernel command line
ROLE=""
FILE=""
for param in $(cat /proc/cmdline); do
    case "$param" in
        ppcopy_role=*) ROLE="${param#ppcopy_role=}" ;;
        ppcopy_file=*)  FILE="${param#ppcopy_file=}" ;;
    esac
done

if [ -z "$ROLE" ] || [ -z "$FILE" ]; then
    echo "PPCOPY_TEST_FAILED: missing ppcopy_role or ppcopy_file kernel params" > /dev/ttyS0
    poweroff -f
fi

case "$ROLE" in
    writer)
        echo "ppcopy-test: writer starting, file=$FILE" > /dev/ttyS0
        /ppwrite-i386 "$FILE"
        RC=$?
        if [ "$RC" -eq 0 ]; then
            echo "ppcopy-test: writer finished OK" > /dev/ttyS0
        else
            echo "PPCOPY_TEST_FAILED: ppwrite-i386 exited with code $RC" > /dev/ttyS0
        fi
        ;;
    reader)
        echo "ppcopy-test: reader starting, expected=$FILE" > /dev/ttyS0
        /ppread-i386 > /received.bin
        RC=$?
        if [ "$RC" -ne 0 ]; then
            echo "PPCOPY_TEST_FAILED: ppread-i386 exited with code $RC" > /dev/ttyS0
            poweroff -f
        fi
        EXPECTED_MD5=$(md5sum "$FILE" | cut -d' ' -f1)
        ACTUAL_MD5=$(md5sum /received.bin | cut -d' ' -f1)
        if [ "$EXPECTED_MD5" = "$ACTUAL_MD5" ]; then
            echo "PPCOPY_TEST_PASSED" > /dev/ttyS0
        else
            echo "PPCOPY_TEST_FAILED: md5 mismatch expected=$EXPECTED_MD5 actual=$ACTUAL_MD5" > /dev/ttyS0
        fi
        ;;
    *)
        echo "PPCOPY_TEST_FAILED: unknown role '$ROLE'" > /dev/ttyS0
        ;;
esac

poweroff -f
