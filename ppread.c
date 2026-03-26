// vim: sw=8 ts=8 noet
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ppcopy.h"

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

	high = read_octet(META_ACK);
	low = read_octet(META_ACK);

	return high << 8 | low;
}

int main(void)
{
	static unsigned char packet_buf[65536];
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
			buf[5] = read_octet(META_ACK);
		}
	}

	while (1) {
		size = read_word();
		if (size == 0)
			break;
		fprintf(stderr, "size = (%05d)\n", size);

		checksum = read_word();
		fprintf(stderr, "checksum = (%04x)\n", checksum);

		fprintf(stderr, "Reading data\n");
		sum = 0;
		for (i = 0; i < size; i++) {
			packet_buf[i] = read_octet(DATA_ACK);
			sum += packet_buf[i];
		}

		fwrite(packet_buf, 1, size, fout);

		if (sum != checksum) {
			fprintf(stderr, "WARNING: checksum mismatch - expected %x, got %x\n",
				checksum, sum);
		}
	}

	fclose(fout);
	return 0;
}
