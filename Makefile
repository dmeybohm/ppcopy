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

.PHONY: all linux linux-i386 dos clean

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

# Clean all build artifacts
clean:
	rm -f par-read par-read.o par-write par-write.o ppcopy.o parread.com parwrite.com \
		ppcopy-i386.o par-read-i386.o par-read-i386 par-write-i386.o par-write-i386
