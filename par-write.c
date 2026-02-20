// vim: sw=8 ts=8 noet
#include <stdio.h>
#include <time.h>
#include <sys/stat.h>
#include <stdlib.h>

#include "ppcopy.h"

#define BLOCK_SIZE	32768

static unsigned char write_ackd(unsigned char data, unsigned char clock)
{
	write_data(data, clock);
	return read_noack(clock);
}

static void write_octet(unsigned char byte, unsigned char expected_ack)
{
	unsigned char byte_low, byte_high;
	unsigned char ack_low, ack_high;

	byte_low = byte & 0x0f;
	byte_high = (byte >> 4) & 0x0f;

	ack_low = write_ackd(byte_low, 0x00);
	ack_high = write_ackd(byte_high, 0x10);
	if (expected_ack && (ack_low != expected_ack || ack_high != expected_ack)) {
		fprintf(stderr, "error: expected %s but received %s\n",
			expected_ack == DATA_ACK ? "DATA_ACK" : "META_ACK",
			ack_low == DATA_ACK ? "DATA_ACK" : "META_ACK");
		exit(1);
	}
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
	FILE *fp;
	time_t begin, end;
	static unsigned char buf[BLOCK_SIZE];
	struct stat statbuf;
	off_t total_size, remaining, sent;
	unsigned short chunk_size, sum, i;

	if (ioperm(BASEPORT, 8, 1)) { perror("ioperm"); exit(1); }

	if (argc != 2) {
		fprintf(stderr, "usage: par-write <file>\n");
		exit(1);
	}

	fp = fopen(argv[1], "rb");
	if (fp == NULL) {
		perror("fopen");
		exit(1);
	}
	if (fstat(fileno(fp), &statbuf) < 0) {
		perror("fstat");
		exit(1);
	}
	total_size = statbuf.st_size;

	begin = time(NULL);

	/* padding byte absorbs possible nibble desync if reader starts first;
	 * sent without ack validation because the reader may not have started */
	write_octet(0x00, 0);

	/* start sequence — reader scans for "ppcopy" to self-synchronize */
	const char *start_seq = "ppcopy";
	for (int j = 0; j < 6; j++)
		write_octet(start_seq[j], META_ACK);

	fprintf(stderr, "sending %ld bytes\n", (long) total_size);

	remaining = total_size;
	sent = 0;
	while (remaining > 0) {
		chunk_size = remaining > BLOCK_SIZE ? BLOCK_SIZE : (unsigned short) remaining;

		/* read one chunk into buf */
		if (fread(buf, 1, chunk_size, fp) != chunk_size) {
			perror("fread");
			exit(1);
		}

		/* compute checksum for this chunk */
		sum = 0;
		for (i = 0; i < chunk_size; i++)
			sum += buf[i];

		/* send size word (big-endian) */
		write_octet((chunk_size >> 8) & 0xff, META_ACK);
		write_octet(chunk_size & 0xff, META_ACK);

		/* send checksum word (big-endian) */
		write_octet((sum >> 8) & 0xff, META_ACK);
		write_octet(sum & 0xff, META_ACK);

		/* send data */
		for (i = 0; i < chunk_size; i++) {
			print_status(sent + i, total_size);
			write_octet(buf[i], DATA_ACK);
		}

		sent += chunk_size;
		remaining -= chunk_size;
	}

	/* send terminator: size=0 */
	write_octet(0x00, META_ACK);
	write_octet(0x00, META_ACK);

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
	return 0;
}
