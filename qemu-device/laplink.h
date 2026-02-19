/*
 * QEMU LapLink Parallel Port Device
 *
 * Emulates a LapLink cable connection between two QEMU instances
 * using a shared memory file for the crossover wiring.
 *
 * Copyright (c) 2025 David Meybohm
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef HW_LAPLINK_H
#define HW_LAPLINK_H

#include "hw/isa/isa.h"
#include "system/ioport.h"
#include "qom/object.h"

#define TYPE_ISA_LAPLINK "isa-laplink"
OBJECT_DECLARE_SIMPLE_TYPE(LapLinkState, ISA_LAPLINK)

struct LapLinkState {
    ISADevice parent_obj;

    /* Properties */
    char *file;
    uint32_t side;
    uint32_t iobase;

    /* State */
    uint8_t dataw;
    uint8_t control;

    /* Shared memory */
    uint8_t *shared_mem;
    int fd;

    PortioList portio_list;
};

#endif /* HW_LAPLINK_H */
