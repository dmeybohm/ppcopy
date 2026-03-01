# QEMU LapLink Parallel Port Device

A QEMU ISA device that emulates a LapLink cable connection between two VMs
using a shared memory file.

## Integration into QEMU Source Tree

### 1. Copy source files

```sh
cp laplink.c /path/to/qemu/hw/char/laplink.c
cp laplink.h /path/to/qemu/include/hw/char/laplink.h
```

### 2. Fix the include path

In the copied `hw/char/laplink.c`, change:

```c
#include "laplink.h"
```

to:

```c
#include "hw/char/laplink.h"
```

### 3. Add Kconfig entry

Append to `hw/char/Kconfig`:

```
config LAPLINK
    bool
    default y
    depends on ISA_BUS
```

### 4. Add to meson build

Add the following line to `hw/char/meson.build`:

```meson
system_ss.add(when: 'CONFIG_LAPLINK', if_true: files('laplink.c'))
```

### 5. Build QEMU

```sh
cd /path/to/qemu
mkdir -p build && cd build
../configure --target-list=i386-softmmu
ninja
```

## Usage

Create a 2-byte shared state file:

```sh
truncate -s 2 /tmp/laplink.state
```

Start two VMs, each taking one side of the cable. Use `-parallel none` to
disable the default parallel port device (which also uses port 0x378):

```sh
# VM A (side 0):
qemu-system-i386 ... -parallel none -device isa-laplink,file=/tmp/laplink.state,side=0

# VM B (side 1):
qemu-system-i386 ... -parallel none -device isa-laplink,file=/tmp/laplink.state,side=1
```

Run `ppwrite.com <file>` in one VM and `ppread.com` in the other to transfer files.

## Verification

Use the QEMU monitor to verify the device is present:

```
(qemu) info qtree
```

The device should appear as `isa-laplink` with the configured `iobase`, `side`, and `file` properties.
