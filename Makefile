# Unified Makefile for ppcopy - builds both Linux and DOS utilities

# Compiler and assembler settings
CC = gcc
CFLAGS = -g -Wall -O2
CC32 = gcc
CFLAGS32 = -g -Wall -O2 -m32 -static
AS = nasm
ASFLAGS = -fbin

# Debug level for assembly builds (0=minimal, 1=errors, 2=verbose)
DEBUG ?= 0

.PHONY: all linux linux-i386 dos clean download-images download-freedos download-alpine download-qemu update-floppies

# Default target - build everything
all: par-read par-write parread.com parwrite.com

# Build only Linux programs
linux: par-read par-write

# Build only DOS programs
dos: parread.com parwrite.com

# Build 32-bit static Linux programs
linux-i386: par-read-i386 par-write-i386

# Shared library
ppcopy.o: ppcopy.c ppcopy.h
	$(CC) $(CFLAGS) -c -o $@ $<

# Linux C programs
par-read: par-read.o ppcopy.o
	$(CC) $(CFLAGS) -o $@ $^

par-read.o: par-read.c ppcopy.h
	$(CC) $(CFLAGS) -c -o $@ $<

par-write: par-write.o ppcopy.o
	$(CC) $(CFLAGS) -o $@ $^

par-write.o: par-write.c ppcopy.h
	$(CC) $(CFLAGS) -c -o $@ $<

# 32-bit static Linux C programs
ppcopy-i386.o: ppcopy.c ppcopy.h
	$(CC32) $(CFLAGS32) -c -o $@ $<

par-read-i386.o: par-read.c ppcopy.h
	$(CC32) $(CFLAGS32) -c -o $@ $<

par-read-i386: par-read-i386.o ppcopy-i386.o
	$(CC32) $(CFLAGS32) -o $@ $^

par-write-i386.o: par-write.c ppcopy.h
	$(CC32) $(CFLAGS32) -c -o $@ $<

par-write-i386: par-write-i386.o ppcopy-i386.o
	$(CC32) $(CFLAGS32) -o $@ $^

# DOS assembly programs
parread.com: parread.nasm
	$(AS) $(ASFLAGS) -DDEBUG=$(DEBUG) $< -o $@

parwrite.com: parwrite.nasm
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
	mcopy -i qemu-device/images/ppcopy-dos.img parread.com parwrite.com ::
	mcopy -i qemu-device/images/ppcopy-dos2.img parread.com parwrite.com ::
	mformat -i qemu-device/images/ppcopy-linux.img -C -f 1440 ::
	mformat -i qemu-device/images/ppcopy-linux2.img -C -f 1440 ::
	cp par-read-i386 par-read-i386.stripped
	cp par-write-i386 par-write-i386.stripped
	strip --strip-all par-read-i386.stripped par-write-i386.stripped
	mcopy -i qemu-device/images/ppcopy-linux.img par-read-i386.stripped ::par-read-i386
	mcopy -i qemu-device/images/ppcopy-linux.img par-write-i386.stripped ::par-write-i386
	mcopy -i qemu-device/images/ppcopy-linux2.img par-read-i386.stripped ::par-read-i386
	mcopy -i qemu-device/images/ppcopy-linux2.img par-write-i386.stripped ::par-write-i386
	rm -f par-read-i386.stripped par-write-i386.stripped

# Clean all build artifacts
clean:
	rm -f par-read par-read.o par-write par-write.o ppcopy.o parread.com parwrite.com \
		ppcopy-i386.o par-read-i386.o par-read-i386 par-write-i386.o par-write-i386 \
		par-read-i386.stripped par-write-i386.stripped
