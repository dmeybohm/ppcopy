// vim: sw=8 ts=8 noet
#include "ppcopy.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

unsigned short base_port = DEFAULT_PORT;

void setup_port(const char *arg)
{
	if (arg != NULL) {
		char *end;
		unsigned long port = strtoul(arg, &end, 16);

		if (*arg == '\0' || *end != '\0' || port == 0 || port > 0xffff - 2) {
			fprintf(stderr, "error: bad port address '%s' "
				"(expected hex, e.g. 278)\n", arg);
			exit(1);
		}
		base_port = (unsigned short) port;
	}
	if (ioperm(base_port, 3, 1)) { perror("ioperm"); exit(1); }
}

void write_data(unsigned char data, unsigned int clock)
{
	data &= 0x0f;
	outb(data | clock, base_port);
}

unsigned char read_noack(unsigned char clock)
{
	unsigned char c0, c1;

	while (1) {
		c0 = inb(base_port + 1) >> 3;
		if ((c0 & 0x10) ^ clock)  {
			c1 = inb(base_port + 1) >> 3;
			if (c0 == c1)
				break;
		}
	}
	return (c0 & 0x0f);
}
