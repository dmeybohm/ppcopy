AS = nasm
ASFLAGS = -fbin

parread.com: parread.nasm
	$(AS) $(ASFLAGS) $? -o $@
	mcopy $@ z:
