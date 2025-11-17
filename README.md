# ppcopy

Copy files over the parallel port using Linux and DOS.

## Building

To build everything (both Linux and DOS utilities), type:

```sh
make
```

This builds all four programs:
- `par-read` and `par-write` (Linux utilities)
- `parread.com` and `parclear.com` (DOS utilities)

### Requirements

- **GCC** (or compatible C compiler) for Linux utilities
- **[NASM](https://www.nasm.us/)** (Netwide Assembler) for DOS utilities

### Build Options

The DOS assembly programs support different debug levels:

```sh
make parread.com DEBUG=0   # Minimal size (188 bytes, default)
make parread.com DEBUG=1   # With error messages (287 bytes)
make parread.com DEBUG=2   # Verbose debugging (571 bytes)
```

The `DEBUG=0` build is optimized for manual entry via the DOS `DEBUG` utility.

## Usage

### Usage on Linux

This consists of two utilities: a way to write a file to the parallel port from
Linux, and another to read.

First, connect the LapLink cable. Then, on one computer, type:

```sh
par-write <file>
```

Replacing `<file>` with whatever file you want to copy.

On the other computer type:

```sh
par-read > <output>
```

Replacing `<output>` with whatever file you want to copy.

The file will be written to `<output>`

### Usage on DOS

There is an assembly language version that you can use for reading on DOS. It
consists of two .COM programs, `parclear.com` and `parread.com`. They are
optimized to be small so that you can load them via the `debug` utility if you
have no other way of copying files to the DOS machine.

To use it, connect a LapLink cable between the Linux computer and the DOS
machine. On the DOS computer, run 

```cmd
parclear
```

After that, then, run `par-write` on the Linux computer. 

Finally, on the DOS computer you're copying to, run

```
parread
```

The output will be placed in `C:\parread.out`.
