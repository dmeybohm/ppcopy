// vim: sw=8 ts=8 noet
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <setjmp.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <sys/io.h>

#define BLOCK_SIZE	32768

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
	return (c0 & 0x0f);
}

static unsigned char write_ackd(unsigned char data, unsigned char clock)
{
	unsigned char ack;

	write_data(data, clock);
	ack = read_noack(clock);
	return ack;
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

static void print_status(off_t sent, off_t total)
{
	int to_print, i;

	if (total == 0)
		return;

	to_print = (int)(sent * NR_HASHES / total);
	if (sent == total)
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
	off_t total_size, remaining, sent;
	unsigned short chunk_size, sum, i;

	if (ioperm(BASEPORT, 8, 1)) { perror ("ioperm"); exit(1); }

	if (argc != 2) {
		fprintf(stderr, "usage: par-write <file>\n");
		exit(1);
	}

	fd = open(argv[1], O_RDONLY);
	if (fd < 0) {
		perror("open");
		exit(1);
	}
	if (fstat(fd, &statbuf) < 0) {
		perror("fstat");
		exit(1);
	}
	total_size = statbuf.st_size;
	p = mmap(0, total_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (p == MAP_FAILED) {
		perror("mmap");
		exit(1);
	}

	write_data(0x00, 0x0);
	begin = time(NULL);

	/* padding byte absorbs possible nibble desync if reader starts first */
	write_octet(0x00);
	/* start sequence — reader scans for "ppcopy" to self-synchronize */
	write_octet('p');
	write_octet('p');
	write_octet('c');
	write_octet('o');
	write_octet('p');
	write_octet('y');

	fprintf(stderr, "sending %ld bytes\n", (long) total_size);

	remaining = total_size;
	sent = 0;
	while (remaining > 0) {
		chunk_size = remaining > BLOCK_SIZE ? BLOCK_SIZE : (unsigned short) remaining;

		/* compute checksum for this chunk */
		sum = 0;
		for (i = 0; i < chunk_size; i++)
			sum += p[sent + i];

		/* send size word (big-endian) */
		write_octet((chunk_size >> 8) & 0xff);
		write_octet(chunk_size & 0xff);

		/* send checksum word (big-endian) */
		write_octet((sum >> 8) & 0xff);
		write_octet(sum & 0xff);

		/* send data */
		for (i = 0; i < chunk_size; i++) {
			print_status(sent + i, total_size);
			write_octet(p[sent + i]);
		}

		sent += chunk_size;
		remaining -= chunk_size;
	}

	/* send terminator: size=0 */
	write_octet(0x00);
	write_octet(0x00);

	print_status(total_size, total_size);
	printf("\n");

	end = time(NULL);
	if (end > begin) {
		fprintf(stderr, "%ld bytes / %lu seconds = %lu bytes/second\n",
			(long) total_size, (unsigned long)(end - begin),
			((unsigned long) total_size) / ((unsigned long)(end - begin)));
	} else {
		fprintf(stderr, "%ld bytes in < 1 second\n", (long) total_size);
	}
	exit (0);
}
