// vim: sw=8 ts=8 noet
#ifndef PPCOPY_H
#define PPCOPY_H

#include <sys/io.h>
#include <unistd.h>

enum {
	BASEPORT  = 0x378,
	DATAPORT  = BASEPORT + 1,
	DELAY     = 1,
	META_ACK  = 0x1,
	DATA_ACK  = 0x2,
};

void write_data(unsigned char data, unsigned int clock);
unsigned char read_noack(unsigned char clock);

#endif
