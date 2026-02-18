// vim: sw=8 ts=8 noet
#ifndef PPCOPY_H
#define PPCOPY_H

#include <sys/io.h>
#include <unistd.h>

#define BASEPORT	0x378
#define DATAPORT	(BASEPORT+1)

#define DELAY		1

void write_data(unsigned char data, unsigned int clock);
unsigned char read_noack(unsigned char clock);

#endif
