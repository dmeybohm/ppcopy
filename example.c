/*
 * example.c: very simple example of port I/O
 *
 * This code does nothing useful, just a port write, a pause,
 * and a port read. Compile with `gcc -O2 -o example example.c',
 * and run as root with `./example'.
 */

#include <stdio.h>
#include <unistd.h>
#include <asm/io.h>

#define BASEPORT 0x278 /* lp1 */
#define SOUNDPORT 0x220 /* sb */

int main()
{
    int i;
    char data[16];

    /* Get access to the ports */
    if (ioperm(SOUNDPORT, 16, 1)) {perror("ioperm"); exit(1);}

#if 0
    /* Set the data signals (D0-7) of the port to all low (0) */
    for (i = 7; i >= 0; --i)
        outw(i<<1, SOUNDPORT+i);

    /* Sleep for a while (100 ms) */
    usleep(100000);

#endif
    /* Read from the status port (BASE+1) and display the result */
    for (i = 0; i < 16; i++) {
	data[i] = inb(SOUNDPORT+i);
	printf("%x: %x\n", SOUNDPORT+i, data[i]);
    }

    /* We don't need the ports anymore */
    if (ioperm(SOUNDPORT, 3, 0)) {perror("ioperm"); exit(1);}

    exit(0);
}

/* end of example.c */
