// vim: sw=8 ts=8 noet
#ifndef PPCOPY_H
#define PPCOPY_H

#include <sys/io.h>
#include <unistd.h>

enum {
	DEFAULT_PORT = 0x378,
	META_ACK  = 0x1,
	DATA_ACK  = 0x2,
};

/* parallel port base address; the status port is base_port + 1 */
extern unsigned short base_port;

/* Parse an optional hex base address (e.g. "278" or "0x278") from argv,
 * set base_port, and request I/O permission.  Exits on error. */
void setup_port(const char *arg);

void write_data(unsigned char data, unsigned int clock);
unsigned char read_noack(unsigned char clock);

#endif
