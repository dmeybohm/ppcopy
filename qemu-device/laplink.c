/*
 * QEMU LapLink Parallel Port Device
 *
 * Emulates a LapLink cable connection between two QEMU instances
 * using a shared memory file for the crossover wiring.
 *
 * The LapLink cable maps 5 data output bits (0-4) from one side to
 * 5 status input bits (3-7) on the other side, with bit 7 (BUSY)
 * inverted by the hardware.
 *
 * Two QEMU instances share a 2-byte file:
 *   byte 0 = side 0's data output (bits 0-4)
 *   byte 1 = side 1's data output (bits 0-4)
 *
 * Copyright (c) 2025 David Meybohm
 *
 * SPDX-License-Identifier: MIT
 */

#include "qemu/osdep.h"
#include "qapi/error.h"
#include "qemu/module.h"
#include "hw/core/qdev-properties.h"
#include "migration/vmstate.h"
#include "laplink.h"

#define LAPLINK_REG_DATA    0
#define LAPLINK_REG_STATUS  1
#define LAPLINK_REG_CONTROL 2

static uint32_t laplink_ioport_read(void *opaque, uint32_t addr)
{
    LapLinkState *s = opaque;

    addr &= 7;
    switch (addr) {
    case LAPLINK_REG_DATA:
        return s->dataw;

    case LAPLINK_REG_STATUS:
        /*
         * LapLink crossover: the other side's 5 data bits (0-4) appear
         * as our status bits (3-7). Bit 7 (BUSY) is inverted by real
         * parallel port hardware.
         */
        return (s->shared_mem[1 - s->side] << 3) ^ 0x80;

    case LAPLINK_REG_CONTROL:
        return s->control;

    default:
        return 0xff;
    }
}

static void laplink_ioport_write(void *opaque, uint32_t addr, uint32_t val)
{
    LapLinkState *s = opaque;

    addr &= 7;
    switch (addr) {
    case LAPLINK_REG_DATA:
        s->dataw = val;
        s->shared_mem[s->side] = val & 0x1f;
        break;

    case LAPLINK_REG_STATUS:
        /* Status register is read-only on real hardware */
        break;

    case LAPLINK_REG_CONTROL:
        s->control = val;
        break;
    }
}

static const MemoryRegionPortio laplink_portio_list[] = {
    { 0, 3, 1,
      .read = laplink_ioport_read,
      .write = laplink_ioport_write },
    PORTIO_END_OF_LIST(),
};

static const VMStateDescription vmstate_laplink = {
    .name = "isa-laplink",
    .version_id = 1,
    .minimum_version_id = 1,
    .fields = (const VMStateField[]) {
        VMSTATE_UINT8(dataw, LapLinkState),
        VMSTATE_UINT8(control, LapLinkState),
        VMSTATE_END_OF_LIST()
    }
};

static void laplink_realizefn(DeviceState *dev, Error **errp)
{
    ISADevice *isadev = ISA_DEVICE(dev);
    LapLinkState *s = ISA_LAPLINK(dev);
    int fd;

    if (!s->file || s->file[0] == '\0') {
        error_setg(errp, "isa-laplink: 'file' property is required");
        return;
    }

    if (s->side > 1) {
        error_setg(errp, "isa-laplink: 'side' must be 0 or 1");
        return;
    }

    fd = open(s->file, O_RDWR);
    if (fd < 0) {
        error_setg_errno(errp, errno,
                         "isa-laplink: failed to open '%s'", s->file);
        return;
    }

    s->shared_mem = mmap(NULL, 2, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (s->shared_mem == MAP_FAILED) {
        error_setg_errno(errp, errno,
                         "isa-laplink: failed to mmap '%s'", s->file);
        close(fd);
        s->shared_mem = NULL;
        return;
    }

    s->fd = fd;

    isa_register_portio_list(isadev, &s->portio_list, s->iobase,
                             laplink_portio_list, s, "laplink");
}

static void laplink_unrealizefn(DeviceState *dev)
{
    LapLinkState *s = ISA_LAPLINK(dev);

    if (s->shared_mem) {
        munmap(s->shared_mem, 2);
        s->shared_mem = NULL;
    }
    if (s->fd >= 0) {
        close(s->fd);
        s->fd = -1;
    }
}

static const Property laplink_properties[] = {
    DEFINE_PROP_STRING("file", LapLinkState, file),
    DEFINE_PROP_UINT32("side", LapLinkState, side, 0),
    DEFINE_PROP_UINT32("iobase", LapLinkState, iobase, 0x378),
};

static void laplink_class_initfn(ObjectClass *klass, const void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);

    dc->realize = laplink_realizefn;
    dc->unrealize = laplink_unrealizefn;
    dc->vmsd = &vmstate_laplink;
    device_class_set_props(dc, laplink_properties);
    set_bit(DEVICE_CATEGORY_INPUT, dc->categories);
}

static const TypeInfo laplink_info = {
    .name          = TYPE_ISA_LAPLINK,
    .parent        = TYPE_ISA_DEVICE,
    .instance_size = sizeof(LapLinkState),
    .class_init    = laplink_class_initfn,
};

static void laplink_register_types(void)
{
    type_register_static(&laplink_info);
}

type_init(laplink_register_types)
