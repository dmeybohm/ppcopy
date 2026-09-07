# Hacking on ppcopy

Developer notes for ppcopy. For usage, see [README.md](README.md).

## Build targets

`make` builds all four programs: `ppread` and `ppwrite` for Linux, and
`ppread.com` and `ppwrite.com` for DOS. You need GCC (or a compatible C
compiler) and [NASM](https://www.nasm.us/).

To build specific targets:

```sh
make linux            # Linux programs (ppread, ppwrite)
make linux-i386       # 32-bit statically linked Linux programs (ppread-i386, ppwrite-i386)
make build-musl-i386  # Build a 32-bit musl toolchain so linux-i386 produces small binaries
make linux-x64        # 64-bit statically linked Linux programs (ppread-x64, ppwrite-x64; needs musl-gcc)
make dos              # DOS programs (ppread.com, ppwrite.com)
```

## DOS build options

The DOS assembly programs support different debug levels:

```sh
make ppread.com DEBUG=0   # Minimal size (237 bytes, default)
make ppread.com DEBUG=1   # With error messages (339 bytes)
make ppread.com DEBUG=2   # Verbose debugging (569 bytes)

make ppwrite.com DEBUG=0  # Minimal size (422 bytes, default)
make ppwrite.com DEBUG=1  # With error messages (467 bytes)
make ppwrite.com DEBUG=2  # Verbose debugging (629 bytes)
```

Error and debug messages go directly to the screen and never end up in the
redirected output file.

By default the DOS programs accept an optional parallel port address on the
command line. That support can be assembled out to save around fifty bytes,
which helps when typing the program in by hand with the DOS `DEBUG` utility;
the port is then fixed at `378`:

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

### Test requirements

- **QEMU** with the LapLink device, built into `qemu/install` by `make download-qemu`
  (needs `git`, `python3`, `ninja-build`, `pkg-config`, `libglib2.0-dev`, `libpixman-1-dev`)
- **FreeDOS and Alpine images**, fetched by `make download-images` (needs `wget`, `unzip`)
- **gcc-multilib** (for building `linux-i386` static binaries, with or without the musl toolchain)
- **mtools**, **genisoimage** (for `isoinfo`), and **cpio** for building the test floppy and initramfs images

Paths are all relative to the checkout; nothing needs to be installed outside it
apart from the packages above.

The QEMU device that emulates a LapLink cable between two VMs lives in
`qemu-device/`. See [qemu-device/README.md](qemu-device/README.md) for how to
integrate it into a QEMU source tree.

## Protocol

See [PROTOCOL.md](PROTOCOL.md) for the wire protocol. `ppread.nasm` is the
source of truth; the C implementations follow it.
