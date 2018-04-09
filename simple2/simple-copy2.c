#include <asm/io.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* Acknowledgement codes */
#define START_ACK	0xb
#define DATA_ACK	0x2

#define START_MAGIC	0xd7

#define BASEPORT	0x378
#define DATAPORT	(BASEPORT+1)

#define DELAY 		1

static void write_data(unsigned char data, unsigned int clock)
{
	data &= 0x0f;
	outb(data | clock, BASEPORT);
}

static unsigned char read_noack(unsigned char clock)
{
	unsigned char c0, c1;

	while (1) {
		c0 = inb(DATAPORT) >> 3;
		usleep(DELAY);
		if ((c0 & 0x10) ^ clock)  {
			c1 = inb(DATAPORT) >> 3;
			if (c0 == c1)
				break;
		}
	}
#if 0
	fprintf(stderr, "read_status(clock=%x,data=%x)\n",clock,c0);
#endif
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
	unsigned low, high;

	low = read_status(0x00, ack);
	high = read_status(0x10, ack);

	return (high << 4 | low);
}

unsigned short read_word(void)
{
	unsigned char low, high;

	low = read_octet(DATA_ACK);
	high = read_octet(DATA_ACK);

	return (high << 8 | low);
}

int main(int argc, char *argv[])
{
	unsigned char *p;
	unsigned short checksum, size;
	unsigned short sum = 0, i;
	FILE * fout;
	
	if (ioperm(BASEPORT, 8, 1)) { perror("ioperm"); exit(1); }

	if (argc != 2) {
		fprintf(stderr, "Usage: simple-copy <file>\n");
		exit(1);
	}

	fout = fopen(argv[1], "w");
	if (!fout) {
		perror("fopen");
		exit(1);
	}

again:
	write_data(0x00, 0x10);
	while ((size = read_octet(START_ACK) != START_MAGIC))
		printf("read: (%x)\n", size);

	checksum = read_word();
	printf("checksum = (%04x)\n", checksum);
	size = read_word();
	printf("size = (%05d)\n", size);
	p = malloc(size);

	printf("Reading data\n");
	for (i = 0; i < size; i++) {
		printf("\r%d", i);
		p[i] = read_octet(DATA_ACK);
		sum += p[i];
		if (i % 50 == 0)
			fflush(stdout);
	}

	if (sum != checksum) {
		read_status(0x00, 5);
		read_status(0x10, 5 ^ 0xf);
		fprintf(stderr, "checksum (%04x) != (%04x)\n", checksum, sum);
		goto again;
	}
	else {
		read_octet(DATA_ACK);
	}

	fwrite(p, sizeof(char), size, fout);
	fclose(fout);

	return 0;
}
