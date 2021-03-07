CFLAGS = -g -Wall -O2

.PHONY: ALL
ALL: simple-copy2 par-write

simple-copy: simple-copy2.o
simple-copy.o: simple-copy2.c
par-write: par-write.o
par-write.o: par-write.c

