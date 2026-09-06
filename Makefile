# Unified Makefile for ppcopy - builds both Linux and DOS utilities

# Compiler and assembler settings
CC = gcc
CFLAGS = -g -Wall -O2
CC32 = gcc
CFLAGS32 = -g -Wall -O2 -m32 -static
CC_X64 = musl-gcc
CFLAGS_X64 = -g -Wall -O2 -static
AS = nasm
ASFLAGS = -fbin

# Debug level for assembly builds (0=minimal, 1=errors, 2=verbose)
DEBUG ?= 0

.PHONY: all linux linux-i386 linux-x64 dos clean download-images download-freedos download-alpine download-qemu update-floppies test

# Default target - build everything
all: ppread ppwrite ppread.com ppwrite.com

# Build only Linux programs
linux: ppread ppwrite

# Build only DOS programs
dos: ppread.com ppwrite.com

# Build 32-bit static Linux programs
linux-i386: ppread-i386 ppwrite-i386

# Shared library
ppcopy.o: ppcopy.c ppcopy.h
	$(CC) $(CFLAGS) -c -o $@ $<

# Linux C programs
ppread: ppread.o ppcopy.o
	$(CC) $(CFLAGS) -o $@ $^

ppread.o: ppread.c ppcopy.h
	$(CC) $(CFLAGS) -c -o $@ $<

ppwrite: ppwrite.o ppcopy.o
	$(CC) $(CFLAGS) -o $@ $^

ppwrite.o: ppwrite.c ppcopy.h
	$(CC) $(CFLAGS) -c -o $@ $<

# 32-bit static Linux C programs
ppcopy-i386.o: ppcopy.c ppcopy.h
	$(CC32) $(CFLAGS32) -c -o $@ $<

ppread-i386.o: ppread.c ppcopy.h
	$(CC32) $(CFLAGS32) -c -o $@ $<

ppread-i386: ppread-i386.o ppcopy-i386.o
	$(CC32) $(CFLAGS32) -o $@ $^

ppwrite-i386.o: ppwrite.c ppcopy.h
	$(CC32) $(CFLAGS32) -c -o $@ $<

ppwrite-i386: ppwrite-i386.o ppcopy-i386.o
	$(CC32) $(CFLAGS32) -o $@ $^

# 64-bit static Linux C programs (musl)
linux-x64: ppread-x64 ppwrite-x64

ppcopy-x64.o: ppcopy.c ppcopy.h
	$(CC_X64) $(CFLAGS_X64) -c -o $@ $<

ppread-x64.o: ppread.c ppcopy.h
	$(CC_X64) $(CFLAGS_X64) -c -o $@ $<

ppread-x64: ppread-x64.o ppcopy-x64.o
	$(CC_X64) $(CFLAGS_X64) -o $@ $^

ppwrite-x64.o: ppwrite.c ppcopy.h
	$(CC_X64) $(CFLAGS_X64) -c -o $@ $<

ppwrite-x64: ppwrite-x64.o ppcopy-x64.o
	$(CC_X64) $(CFLAGS_X64) -o $@ $^

# DOS assembly programs
ppread.com: ppread.nasm
	$(AS) $(ASFLAGS) -DDEBUG=$(DEBUG) $< -o $@

ppwrite.com: ppwrite.nasm
	$(AS) $(ASFLAGS) -DDEBUG=$(DEBUG) $< -o $@

# Download distribution images and QEMU
download-images: download-freedos download-alpine download-qemu

download-freedos:
	./qemu-device/download-freedos.sh

download-alpine:
	./qemu-device/download-alpine.sh

download-qemu:
	./qemu-device/download-qemu.sh

# Update floppy images with freshly built binaries
# Images are recreated each time to avoid stale files and ensure correct 1.44MB geometry
# Linux binaries are stripped to fit both on a 1.44MB floppy
update-floppies: linux-i386 dos
	mformat -i qemu-device/images/ppcopy-dos.img -C -f 1440 ::
	mformat -i qemu-device/images/ppcopy-dos2.img -C -f 1440 ::
	mcopy -i qemu-device/images/ppcopy-dos.img ppread.com ppwrite.com ::
	mcopy -i qemu-device/images/ppcopy-dos2.img ppread.com ppwrite.com ::
	mformat -i qemu-device/images/ppcopy-linux.img -C -f 1440 ::
	mformat -i qemu-device/images/ppcopy-linux2.img -C -f 1440 ::
	cp ppread-i386 ppread-i386.stripped
	cp ppwrite-i386 ppwrite-i386.stripped
	strip --strip-all ppread-i386.stripped ppwrite-i386.stripped
	mcopy -i qemu-device/images/ppcopy-linux.img ppread-i386.stripped ::ppread-i386
	mcopy -i qemu-device/images/ppcopy-linux.img ppwrite-i386.stripped ::ppwrite-i386
	mcopy -i qemu-device/images/ppcopy-linux2.img ppread-i386.stripped ::ppread-i386
	mcopy -i qemu-device/images/ppcopy-linux2.img ppwrite-i386.stripped ::ppwrite-i386
	rm -f ppread-i386.stripped ppwrite-i386.stripped

# Run integration tests
test: dos linux-i386
	./tests/run-tests.sh

# Clean all build artifacts
clean:
	rm -f ppread ppread.o ppwrite ppwrite.o ppcopy.o ppread.com ppwrite.com \
		ppcopy-i386.o ppread-i386.o ppread-i386 ppwrite-i386.o ppwrite-i386 \
		ppread-i386.stripped ppwrite-i386.stripped \
		ppcopy-x64.o ppread-x64.o ppread-x64 ppwrite-x64.o ppwrite-x64
