// vim: sw=8 ts=8 noet
#include "ppcopy.h"
#include <unistd.h>

void write_data(unsigned char data, unsigned int clock)
{
	data &= 0x0f;
	outb (data | clock, BASEPORT);
}

unsigned char read_noack(unsigned char clock)
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
