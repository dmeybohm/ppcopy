# Unified Makefile for ppcopy - builds both Linux and DOS utilities

# Compiler and assembler settings
CC = gcc
CFLAGS = -g -Wall -O2
AS = nasm
ASFLAGS = -fbin

# Debug level for assembly builds (0=minimal, 1=errors, 2=verbose)
DEBUG ?= 0

.PHONY: all clean

# Default target - build everything
all: par-read par-write parread.com parclear.com

# Linux C programs
par-read: par-read.o
	$(CC) $(CFLAGS) -o $@ $^

par-read.o: par-read.c
	$(CC) $(CFLAGS) -c -o $@ $<

par-write: par-write.o
	$(CC) $(CFLAGS) -o $@ $^

par-write.o: par-write.c
	$(CC) $(CFLAGS) -c -o $@ $<

# DOS assembly programs
parread.com: parread.nasm
	$(AS) $(ASFLAGS) -DDEBUG=$(DEBUG) $< -o $@

parclear.com: parclear.nasm
	$(AS) $(ASFLAGS) $< -o $@

# Clean all build artifacts
clean:
	rm -f par-read par-read.o par-write par-write.o parread.com parclear.com
