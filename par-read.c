// vim: sw=8 ts=8 noet
#include <sys/io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define DATA_ACK	0x2

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
	*ret = c0 & 0x0f;
	return OK;
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
	unsigned char high, low;

	if (read_octet(DATA_ACK, &high) == TIMEOUT)
		return TIMEOUT;
	if (read_octet(DATA_ACK, &low) == TIMEOUT)
		return TIMEOUT;

	*ret = high << 8 | low;
	return OK;
}

int main(int argc, char *argv[])
{
	unsigned char *p;
	unsigned short checksum, size;
	unsigned short sum, i;
	FILE *fout;

	if (ioperm(BASEPORT, 8, 1)) { perror("ioperm"); exit(1); }

	fout = stdout;

	/* initialize port so writer sees a known state */
	write_data(0x00, 0x10);

	/* scan for "ppcopy" start sequence using sliding window */
	{
		unsigned char buf[6] = {0};
		unsigned char ch;

		while (memcmp(buf, "ppcopy", 6) != 0) {
			if (read_octet(DATA_ACK, &ch) == TIMEOUT) {
				fprintf(stderr, "timed out scanning for start sequence\n");
				continue;
			}
			memmove(buf, buf + 1, 5);
			buf[5] = ch;
		}
	}

	while (1) {
		if (read_word(&size) != OK) {
			fprintf(stderr, "timed out reading size\n");
			break;
		}
		if (size == 0)
			break;
		fprintf(stderr, "size = (%05d)\n", size);

		if (read_word(&checksum) != OK) {
			fprintf(stderr, "timed out reading checksum\n");
			break;
		}
		fprintf(stderr, "checksum = (%04x)\n", checksum);

		p = malloc(size);
		if (p == NULL) {
			fprintf(stderr, "malloc: out of memory\n");
			return 1;
		}

		fprintf(stderr, "Reading data\n");
		sum = 0;
		for (i = 0; i < size; i++) {
			if (read_octet(DATA_ACK, &p[i]) == TIMEOUT) {
				fprintf(stderr, "timed out reading data at byte %d\n", i);
				break;
			}
			sum += p[i];
		}

		fwrite(p, sizeof(char), i, fout);
		free(p);

		if (i < size) {
			fprintf(stderr, "incomplete block, stopping\n");
			break;
		}

		if (sum != checksum) {
			fprintf(stderr, "WARNING: checksum mismatch - expected %x, got %x\n",
				checksum, sum);
		}
	}

	fclose(fout);
	return 0;
}
