#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <setjmp.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <sys/io.h>

#define END_MAGIC 	0xe0
#define COMMIT_MAGIC	0x15
#define START_MAGIC	0xd7

#define BASEPORT	0x378
#define DATAPORT	(BASEPORT+1)

#define DELAY 		1

static void print_current(void)
{
#if 0
	fprintf(stderr, "status(in=%x)\n", inb(DATAPORT)>>3);
#endif
}

static void write_data(unsigned char data, unsigned int clock)
{
	data &= 0x0f;
    outb (data | clock, BASEPORT);
}

static unsigned char read_noack(unsigned char clock)
{
	unsigned char c0, c1;

	while (1) {
		c0 = inb (DATAPORT) >> 3;
		usleep(DELAY);
		if ((c0 & 0x10) ^ clock)  {
			c1 = inb (DATAPORT) >> 3;
			if (c0 == c1)
				break;
		}
	}
#if 0
	fprintf(stderr, "read_status(clock=%x,data=%x)\n", clock, c0);
#endif
	return (c0 & 0x0f);
}

unsigned char write_ackd(unsigned char data, unsigned char clock)
{
	unsigned char ack;

	write_data(data, clock);
	ack = read_noack(clock);
	return ack;
}

unsigned char read_status(unsigned char clock, unsigned char ack)
{
	unsigned char res = read_noack(clock);
	write_data(ack, clock);
	return res;
}

static int write_octet(unsigned char byte)
{
	unsigned char byte_low, byte_high;
	unsigned char ack_low, ack_high;
		
	byte_low = byte & 0x0f;
	byte_high = (byte >> 4) & 0x0f;	

	print_current();
	ack_low = write_ackd(byte_low, 0x00);
	ack_high = write_ackd(byte_high, 0x10);
	if (ack_low != ack_high) 
		fprintf(stderr, "write_octet: Warning: ack_low (%x)!= ack_high"
				" (%x)\n", ack_low, ack_high);
	return (ack_low == ack_high);
}

#define NR_HASHES 40

static int num_hashes = -1;

static void print_status(unsigned short i, unsigned short size)
{
	int to_print = NR_HASHES;

	to_print *= i;
	to_print /= size;

	if (i == size-1)
		to_print = NR_HASHES;
	if (to_print <= num_hashes)
		return;

	num_hashes = to_print;
	printf("\r[");
	for (i = 0; i < to_print; i++)
		printf("#");
	for (; i < NR_HASHES; i++)
		printf(" ");
	printf("]");
	fflush(stdout);
}

int main(int argc, char *argv[])
{
	int fd;
	time_t begin, end;
	unsigned char *p;
	struct stat statbuf;
	unsigned short i, size, sum;

	if (ioperm(BASEPORT, 8, 1)) { perror ("ioperm"); exit(1); }

	if (argc != 2) {
		fprintf(stderr, "usage: par-write <file>\n");
		exit(1);
	}

	fd = open(argv[1], O_RDONLY);
	if (!fd) {
		perror("open");
		exit(1);
	}
	if (fstat(fd, &statbuf) < 0) {
		perror("fstat");
		exit(1);
	}
	size = statbuf.st_size;
	p = mmap(0, size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		exit(1);
	}

	for (sum = i = 0; i < size; i++)
		sum += p[i];

	fprintf(stderr, "checksum = %04x\n", sum);
	
again:
	write_data(0x00, 0x0);
	begin = time(NULL);
	while (!write_octet(START_MAGIC))
		;

	printf("sending checksum: (%04x)\n", sum);
	write_octet(sum & 0xff);
	write_octet((sum >> 8) & 0xff);
	
	printf("sending size: (%5d)\n", size);
	write_octet(size & 0xff);
	write_octet((size >> 8) & 0xff);

	printf("sending data\n");
	for (i = 0; i < size; i++) {
		print_status(i, size);
		write_octet(p[i]);
	}
	printf("\n");
	if (!write_octet(END_MAGIC)) {
		printf("error sending data, resending\n");
		goto again;
	}

	end = time(NULL);
	fprintf(stderr, "%d bytes / %lu seconds = %lu bytes/second\n",
		(unsigned) size, (unsigned) end-begin, ((unsigned) size) / ((unsigned)
		end-begin));
	exit (0);
}
