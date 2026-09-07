# ppcopy

Copy files over the parallel port using Linux and DOS and a
[LapLink cable](http://www.nullmodem.com/LapLink.htm).

The typical use is getting files onto an old DOS machine that has no other
way in: no network, no working floppy drive, no USB. The DOS programs are a
few hundred bytes, small enough to type in by hand with the DOS `DEBUG`
utility, and after that the cable does the rest.

## Getting the programs

### Download

Prebuilt binaries are on the
[releases page](https://github.com/dmeybohm/ppcopy/releases). Each release
contains:

- `ppread.com` and `ppwrite.com` for DOS
- `ppread-i386`, `ppwrite-i386`, `ppread-x64`, and `ppwrite-x64` for Linux.
  These are statically linked and run on any distribution.

### Build from source

You need GCC and [NASM](https://www.nasm.us/). Then:

```sh
make
```

This builds `ppread` and `ppwrite` for Linux and `ppread.com` and
`ppwrite.com` for DOS. Use `make linux` or `make dos` to build only one side.
See [HACKING.md](HACKING.md) for other build variants.

## Copying a file

The commands are the same on Linux and DOS. Connect the LapLink cable between
the two machines, then start the receiver first:

```sh
ppread > output
```

Now, on the other machine, send the file:

```sh
ppwrite file
```

Any combination works: Linux to DOS, DOS to Linux, DOS to DOS, or Linux to
Linux.

On Linux the programs talk to the port directly, so they must run as root:

```sh
sudo ppread > output
sudo ppwrite file
```

`ppread` always writes the received data to standard output, so it must be
redirected to a file. Error messages go to the screen and never end up in the
output file. On DOS the errorlevel is 1 if anything went wrong, including
running out of disk space.

## Bootstrapping a DOS machine with no media

If there is no way to copy `ppread.com` onto the DOS machine, you can type it
in with the DOS `DEBUG` utility. The default build is 237 bytes. A build with
`PORT_ARG=0` drops the port argument and gets it down to 190 bytes; see
[HACKING.md](HACKING.md) for the build flags. Once `ppread.com` is on the
machine, use it to receive everything else, including `ppwrite.com`.

## Using a different parallel port

All programs use the parallel port at I/O address `378` (LPT1 on most
machines) unless told otherwise. To use a different port, give its base
address in hex as the last argument. It is the only argument to `ppread`
and follows the file name for `ppwrite`, on both Linux and DOS:

```sh
ppwrite file 278
ppread 278 > output
```

The usual addresses are `378` for LPT1, `278` for LPT2, and `3bc` for the
port on an old monochrome display adapter. The Linux programs also accept a
`0x` prefix.

The DOS programs do not check the address for typos: anything that is not a
hex digit is silently taken as one. Builds made with `PORT_ARG=0` ignore the
argument entirely and always use `378`.

## More

- [HACKING.md](HACKING.md): build variants, DOS debug builds, making a
  release, running the tests.
- [PROTOCOL.md](PROTOCOL.md): the wire protocol.
- [qemu-device/README.md](qemu-device/README.md): a QEMU device that emulates
  a LapLink cable between two virtual machines.
