// vim: sw=8 ts=8 noet
#include <sys/io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define DATA_ACK	0x2

#define BASEPORT	0x378
#define DATAPORT	(BASEPORT+1)

#define DELAY           1

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

	fprintf(stderr, "read_status(clock=%x,data=%x)\n", clock, c0);
	return (c0 & 0x0f);
}

static unsigned char read_status(unsigned char clock, unsigned char ack)
{
	unsigned char res = read_noack(clock);
	write_data(ack, clock);
	return res;
}

static unsigned char read_octet(unsigned int ack)
{
	unsigned char low, high;

	low = read_status(0x00, ack);
	high = read_status(0x10, ack);

	return high << 4 | low;
}

static unsigned short read_word(void)
{
	unsigned char high, low;

	high = read_octet(DATA_ACK);
	low = read_octet(DATA_ACK);

	return high << 8 | low;
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

		while (memcmp(buf, "ppcopy", 6) != 0) {
			memmove(buf, buf + 1, 5);
			buf[5] = read_octet(DATA_ACK);
		}
	}

	while (1) {
		size = read_word();
		if (size == 0)
			break;
		fprintf(stderr, "size = (%05d)\n", size);

		checksum = read_word();
		fprintf(stderr, "checksum = (%04x)\n", checksum);

		p = malloc(size);
		if (p == NULL) {
			fprintf(stderr, "malloc: out of memory\n");
			return 1;
		}

		fprintf(stderr, "Reading data\n");
		sum = 0;
		for (i = 0; i < size; i++) {
			p[i] = read_octet(DATA_ACK);
			sum += p[i];
		}

		fwrite(p, sizeof(char), size, fout);
		free(p);

		if (sum != checksum) {
			fprintf(stderr, "WARNING: checksum mismatch - expected %x, got %x\n",
				checksum, sum);
		}
	}

	fclose(fout);
	return 0;
}
