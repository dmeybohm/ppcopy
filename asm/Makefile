AS = nasm
ASFLAGS = -fbin

.PHONY: ALL clean
ALL: parread.com parclear.com

parread.com: parread.nasm
	$(AS) $(ASFLAGS) $? -o $@

parclear.com: parread.nasm
	$(AS) $(ASFLAGS) $? -o $@

clean:
	rm -f parread.com parclear.com
