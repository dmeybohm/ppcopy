// vim: sw=8 ts=8 noet
#include <sys/io.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* Acknowledgement codes */
#define START_ACK	0xb
#define DATA_ACK	0x2

#define START_MAGIC	0xd7

#define BASEPORT	0x378
#define DATAPORT	(BASEPORT+1)

#define TIMEOUT         1
#define TIMEOUT_TRIES   10000

#define OK              0
#define DELAY           1

static void write_data(unsigned char data, unsigned int clock)
{
	data &= 0x0f;
	outb (data | clock, BASEPORT);
}

static int read_noack(unsigned char clock, unsigned char *ret)
{
	unsigned char c0, c1;
	unsigned int cx = TIMEOUT_TRIES;

	while (1) {
		c0 = inb (DATAPORT) >> 3;
		usleep(DELAY);
		if ((c0 & 0x10) ^ clock)  {
			c1 = inb (DATAPORT) >> 3;
			if (c0 == c1)
				break;
		}
		if (--cx == 0)
			return TIMEOUT;
	}

	fprintf(stderr, "read_status(clock=%x,data=%x)\n",clock,c0);
	return (c0 & 0x0f);
}

static int read_status(unsigned char clock, unsigned char ack,
                       unsigned char *ret)
{
	if (read_noack(clock, ret) == TIMEOUT)
		return TIMEOUT;

	write_data(ack, clock);
	return OK;
}

static int read_octet(unsigned int ack, unsigned char *ret)
{
	unsigned char low = 0, high = 0;

	if (read_status(0x00, ack, &low) == TIMEOUT)
		return TIMEOUT;
	if (read_status(0x10, ack, &high) == TIMEOUT)
		return TIMEOUT;

	*ret = high << 4 | low;
	return OK;
}

int read_word(unsigned short *ret)
{
	unsigned char low, high;

	if (read_octet(DATA_ACK, &low) == TIMEOUT)
		return TIMEOUT;
	if (read_octet(DATA_ACK, &high) == TIMEOUT)
		return TIMEOUT;

	*ret = high << 8 | low;
	return OK;
}

int main(int argc, char *argv[])
{
	unsigned char *p, start;
	unsigned short checksum, size;
	unsigned short sum = 0, i;
	FILE * fout;
	
	if (ioperm(BASEPORT, 8, 1)) { perror("ioperm"); exit(1); }

	fout = stdout;

	/* reset -- is this necessary? */
	write_data(0x00, 0x10);
again:
	start = 0;
	while (start != START_MAGIC && read_octet(START_ACK, &start) != OK) {
		fprintf(stderr, "timed out reading start magic (read %x)\n", start);
	}

	if (read_word(&checksum) != OK) {
		fprintf(stderr, "timed out reading checksum\n");
		goto again;
	}
	fprintf(stderr, "checksum = (%04x)\n", checksum);

	if (read_word(&size) != OK) {
		fprintf(stderr, "timed out reading size\n");
		goto again;
	}
	printf("size = (%05d)\n", size);

	p = malloc(size);

	fprintf(stderr, "Reading data\n");
	for (i = 0; i < size; i++) {
		fprintf(stderr, "%d\n", i);
		if (read_octet(DATA_ACK, &p[i]) == TIMEOUT) {
			/* print what data is available */
			break;
		}
		sum += p[i];
	}

	fwrite(p, sizeof(char), i, fout);
	fclose(fout);

	if (sum != checksum) {
		fprintf(stderr, "WARNING: checksum mismatch - expected %x, got %x\n", 
			checksum, sum);
	}

	return 0;
}
