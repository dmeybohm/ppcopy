# ppcopy

Copy files over the parallel port using Linux and DOS and a 
[LapLink cable](http://www.nullmodem.com/LapLink.htm).

## Building

To build everything (both Linux and DOS utilities), type:

```sh
make
```

This builds all four programs:
- `ppread` and `ppwrite` (Linux utilities)
- `ppread.com` and `ppwrite.com` (DOS utilities)

### Requirements

- **GCC** (or compatible C compiler) for Linux utilities
- **[NASM](https://www.nasm.us/)** (Netwide Assembler) for DOS utilities

### Build Options

You can build specific targets:

```sh
make linux       # Build only Linux programs (ppread, ppwrite)
make linux-i386  # Build 32-bit statically linked Linux programs (ppread-i386, ppwrite-i386)
make build-musl-i386  # Build a 32-bit musl toolchain so linux-i386 produces small binaries
make linux-x64   # Build 64-bit statically linked Linux programs (ppread-x64, ppwrite-x64; needs musl-gcc)
make dos         # Build only DOS programs (ppread.com, ppwrite.com)
```

The DOS assembly programs support different debug levels:

```sh
make ppread.com DEBUG=0   # Minimal size (237 bytes, default)
make ppread.com DEBUG=1   # With error messages (339 bytes)
make ppread.com DEBUG=2   # Verbose debugging (569 bytes)

make ppwrite.com DEBUG=0  # Minimal size (422 bytes, default)
make ppwrite.com DEBUG=1  # With error messages (467 bytes)
make ppwrite.com DEBUG=2  # Verbose debugging (629 bytes)
```

They also accept an optional parallel port address on the command line
(see [Choosing the parallel port](#choosing-the-parallel-port)). That
support can be assembled out to save around fifty bytes, which helps when
typing the program in by hand with the DOS `DEBUG` utility; the port is then
fixed at `378`:

```sh
make ppread.com PORT_ARG=0   # 190 bytes with DEBUG=0
make ppwrite.com PORT_ARG=0  # 371 bytes with DEBUG=0
```

## Making a release

```sh
./make-release.sh [VERSION]
```

This builds the DOS programs plus static Linux binaries for i386 and x86-64,
strips them, and bundles them with the docs into `dist/ppcopy-VERSION.tar.gz`
and `.zip` with a SHA-256 checksum file. `VERSION` defaults to `git describe`.
It needs `nasm`, `musl-tools` (for `linux-x64`), and the 32-bit musl toolchain
for `linux-i386`. Ubuntu only packages musl for x86_64, so build the 32-bit one
from source once with:

```sh
make build-musl-i386
```

This needs `gcc-multilib` and installs into `musl-i386/` inside the project.
Without it, `linux-i386` still builds but links glibc, which makes the
binaries about twenty times larger; `make-release.sh` refuses to run in that
case.

## Testing

To run the integration tests:

```sh
make test
```

This uses QEMU to run end-to-end transfer tests between all combinations of
DOS and Linux senders/receivers, with both small and large files.

### Test Requirements

- **QEMU** with the LapLink device, built into `qemu/install` by `make download-qemu`
  (needs `git`, `python3`, `ninja-build`, `pkg-config`, `libglib2.0-dev`, `libpixman-1-dev`)
- **FreeDOS and Alpine images**, fetched by `make download-images` (needs `wget`, `unzip`)
- **gcc-multilib** (for building `linux-i386` static binaries, with or without the musl toolchain)
- **mtools**, **genisoimage** (for `isoinfo`), and **cpio** for building the test floppy and initramfs images

Paths are all relative to the checkout; nothing needs to be installed outside it
apart from the packages above.

## Usage

### Usage on Linux

This consists of two utilities: a way to write a file to the parallel port from
Linux, and another to read.

First, connect the LapLink cable. Then, on one computer, type:

```sh
ppwrite <file>
```

Replacing `<file>` with whatever file you want to copy.

On the other computer type:

```sh
ppread > <output>
```

Replacing `<output>` with whatever file you want to copy.

The file will be written to `<output>`

### Choosing the parallel port

All four programs use the parallel port at I/O address `378` (LPT1 on most
machines) unless told otherwise. To use a different port, give its base
address in hex as the last argument. It is the only argument to `ppread`
and follows the file name for `ppwrite`, on both Linux and DOS:

```sh
ppwrite <file> 278
ppread 278 > <output>
```

Only the base address is needed; the status register at the next address
up is found from it. The usual addresses are `378` for LPT1, `278` for
LPT2, and `3bc` for the port on an old monochrome display adapter. The
Linux programs also accept a `0x` prefix.

### Usage on DOS

There are assembly language versions that you can use for reading and writing on
DOS. They consist of two .COM programs: `ppread.com` and `ppwrite.com`. They
are optimized to be small so that you can load them via the `debug` utility if
you have no other way of copying files to the DOS machine.

#### Receiving files on DOS

Connect a LapLink cable between the Linux computer and the DOS machine. Run
`ppwrite` on the Linux computer, and on the DOS computer run

```cmd
ppread > output
```

Replacing `output` with whatever file you want to copy to. `ppread.com`
writes the received data to standard output, just like the Linux version,
so it must be redirected to a file. Error and debug messages (in the
`DEBUG=1` and `DEBUG=2` builds) go directly to the screen and never end up
in the output file. The errorlevel is 1 if anything went wrong, including
running out of disk space.

To read from a port other than `378`, put its hex address before the
redirection, for example `ppread 278 > output`.

#### Sending files from DOS

`ppwrite.com` can send files from DOS, enabling DOS-to-DOS or DOS-to-Linux
transfers without needing a Linux sender. On the DOS computer, run

```cmd
ppwrite <file>
```

On the receiving end, run `ppread` on Linux or `ppread` on another DOS
machine.

To send through a port other than `378`, add its hex address after the
file name, for example `ppwrite <file> 278`.

The DOS programs do not check the address for typos: anything that is not
a hex digit is silently taken as one. Builds made with `PORT_ARG=0` ignore
the argument entirely and always use `378`.

## QEMU Device

A QEMU device that emulates a LapLink cable connection between two VMs is
included in the `qemu-device/` directory. See
[qemu-device/README.md](qemu-device/README.md) for integration and usage
instructions.

## Protocol

See [PROTOCOL.md](PROTOCOL.md) for details on the wire protocol used for
transfers.
