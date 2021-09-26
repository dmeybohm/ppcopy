CFLAGS = -g -Wall -O2

.PHONY: ALL clean
ALL: par-read par-write

par-read: par-read.o
par-read.o: par-read.c
par-write: par-write.o
par-write.o: par-write.c

clean:
	rm -f par-read par-read.o par-write par-write.o
