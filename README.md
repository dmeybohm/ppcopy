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
make ppread.com DEBUG=0   # Minimal size (188 bytes, default)
make ppread.com DEBUG=1   # With error messages (287 bytes)
make ppread.com DEBUG=2   # Verbose debugging (571 bytes)

make ppwrite.com DEBUG=0  # Minimal size (default)
make ppwrite.com DEBUG=1  # With error messages
make ppwrite.com DEBUG=2  # Verbose debugging
```

The `DEBUG=0` build is optimized for manual entry via the DOS `DEBUG` utility.

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

### Usage on DOS

There are assembly language versions that you can use for reading and writing on
DOS. They consist of two .COM programs: `ppread.com` and `ppwrite.com`. They
are optimized to be small so that you can load them via the `debug` utility if
you have no other way of copying files to the DOS machine.

#### Receiving files on DOS

Connect a LapLink cable between the Linux computer and the DOS machine. Run
`ppwrite` on the Linux computer, and on the DOS computer run

```cmd
ppread
```

The output will be placed in `C:\ppread.out`.

#### Sending files from DOS

`ppwrite.com` can send files from DOS, enabling DOS-to-DOS or DOS-to-Linux
transfers without needing a Linux sender. On the DOS computer, run

```cmd
ppwrite <file>
```

On the receiving end, run `ppread` on Linux or `ppread` on another DOS
machine.

## QEMU Device

A QEMU device that emulates a LapLink cable connection between two VMs is
included in the `qemu-device/` directory. See
[qemu-device/README.md](qemu-device/README.md) for integration and usage
instructions.

## Protocol

See [PROTOCOL.md](PROTOCOL.md) for details on the wire protocol used for
transfers.
