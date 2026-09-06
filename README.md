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
It needs `nasm`, `gcc-multilib` (for `linux-i386`) and `musl-tools` (for
`linux-x64`).

## Testing

To run the integration tests:

```sh
make test
```

This uses QEMU to run end-to-end transfer tests between all combinations of
DOS and Linux senders/receivers, with both small and large files.

### Test Requirements

- **QEMU** (built from the `qemu/` submodule — see [qemu-device/README.md](qemu-device/README.md))
- **32-bit GCC libraries** (for building `linux-i386` static binaries)

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
