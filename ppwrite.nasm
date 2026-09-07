;
; ppwrite.nasm -- Send files through a parallel port connected
;                  with a laplink cable from DOS/DOSEMU/FreeDOS
;
;	ppwrite file
;
; An optional hex base address selects a parallel port other than 0x378:
;
;	ppwrite file 278
;

%define BASE_PORT	0x378
%define DATA_PORT	(BASE_PORT+1)
%define CMD_TAIL	0x81		; command line in the PSP, CR-terminated
%define META_ACK	0x1
%define DATA_ACK	0x2

%define BLOCK_SIZE	32767

;
; Turn these off for smaller code,
;   on for more verbosity/safety.
;
%ifndef DEBUG
%define DEBUG		0	; 0, 1, or 2 (can be overridden from command line)
%endif

;
; Accept an optional port address on the command line.  Turn off for the
; smallest possible binary; the port is then fixed at BASE_PORT.
;
%ifndef PORT_ARG
%define PORT_ARG	1	; 0 or 1 (can be overridden from command line)
%endif

; Load the data (base) or status (base+1) port address into dx
%if PORT_ARG
%macro LOAD_BASE 0
	mov dx,[base_port]
%endmacro
%macro LOAD_STATUS 0
	mov dx,[base_port]
	inc dx
%endmacro
%else
%macro LOAD_BASE 0
	mov dx,BASE_PORT
%endmacro
%macro LOAD_STATUS 0
	mov dx,DATA_PORT
%endmacro
%endif

; Used for ``readability'' only
%define PTR(x)		x
%define SYM(x)		x

; Usage: die_if cc, label_2_print
;
; Use short jcc if possible, and jump over 'jmp' otherwise
;
%macro DIE_IF 2
	%if (DEBUG == 0)
		j%+1 exit	; no guarantee this will assemble, but
				; when debugging code is turned off, it's more
				; likely
	%else
		j%-1 %%continue
		mov dx,PTR(%2)
		jmp print_err_and_exit
	%%continue:
	%endif
%endmacro

;
; Use conditional jcc if not debugging, and absolute
; jmp otherwise
;
%macro JMP_IF 2
	%if (DEBUG == 0)
		j%+1 %2
	%else
		j%-1 %%continue
		jmp %2
	%%continue:
	%endif
%endmacro

%macro PRINT_SUCCESS 1
	%if (DEBUG > 0)
		PRINT_INFO %1
	%else
		mov dx,PTR(%1)
		mov ah,0x09
		int 0x21
	%endif
%endmacro

%macro PRINT_INFO 1
	%if (DEBUG > 0)
		mov dx,PTR(%1)
		call print_info
	%endif
%endmacro

%macro DPRINT 1
	%if (DEBUG > 1)
		push dx
		mov dx,PTR(%1)
		call print_info
		pop dx
	%endif
%endmacro

;
; Writer-side wait-for-ack macro (equivalent to C read_noack)
;
; Input: DX = writer clock (0x00 or 0x10)
; Output: AL = ack nibble (low 4 bits)
; Preserves: BX, CX
;
%macro DO_WAIT_ACK 0
	push cx
	push bx
	mov bx,dx		; save clock in BL
	LOAD_STATUS
%%redo:
	in al,dx		; read raw from status port
	mov cl,al		; save raw for stability check
	shr al,3		; shift right 3
	mov ch,al		; save shifted value
	and al,0x10		; isolate clock bit (bit 4)
	xor al,bl		; compare with expected clock
	jz %%redo		; no toggle yet, retry
	in al,dx		; read again (raw)
	cmp al,cl		; stability check (compare raw)
	jne %%redo		; unstable, retry
	mov al,ch		; recover shifted value
	and al,0x0f		; mask to ack nibble
	mov dx,bx		; restore DX
	pop bx
	pop cx
%endmacro

	org 0x100

;
; Main program.
;
; Reads a file in chunks of up to BLOCK_SIZE bytes and sends each
; chunk over the parallel port using the ppcopy wire protocol.
;
start:
	; Parse command line for filename
	mov ax,CMD_TAIL		; start with 0xb8 so file(1) detects COM
	xchg ax,si
	cld
.skip_spaces:
	lodsb
	cmp al,' '
	je .skip_spaces
	cmp al,0x0d
	jne .has_arg
	mov dx,PTR(usage_str)
	mov ah,0x09
	int 0x21
	mov ax,0x4c01
	int 0x21
.has_arg:
	dec si			; back up to first non-space char
	mov dx,si		; DX = start of filename (ASCIIZ)
.find_end:
	lodsb
	cmp al,0x0d
	je .got_end
	cmp al,' '
	jne .find_end
.got_end:
	mov byte [si-1],0	; null-terminate filename
%if PORT_ARG
	cmp al,' '		; a space means a port argument may follow;
	je .open		;   a CR ends the line, so stay on the 0 that
	dec si			;   replaced it and parse_port sees no argument
.open:
%endif

	; Open file for reading
	mov ah,0x3d		; DOS open file
	mov al,0x00		; read-only
	int 0x21
	DIE_IF c,SYM(open_err_str)
	mov bx,ax		; BX = file handle (preserved throughout)

%if PORT_ARG
	call parse_port		; SI still points past the filename
%endif

	; Initialize port
	LOAD_BASE
	xor al,al
	out dx,al

	; Send padding byte without ack validation (reader may not have started)
	mov byte [expected_ack], 0
	xor al,al
	call write_octet

	; Send "ppcopy" start sequence
	mov byte [expected_ack], META_ACK
	mov si,PTR(magic_str)
	mov cx,6
.send_magic:
	lodsb
	call write_octet
	loop .send_magic

send_loop:
	; Read up to BLOCK_SIZE bytes from file
	mov dx,PTR(block)
	mov cx,BLOCK_SIZE
	mov ah,0x3f		; DOS read file
	int 0x21		; BX = handle, CX = count, DS:DX = buffer
	DIE_IF c,SYM(read_err_str)
	test ax,ax
	jz send_terminator	; 0 bytes read = EOF

	mov cx,ax		; CX = bytes_read
	push cx			; save bytes_read for final comparison

	; Compute checksum
	mov si,PTR(block)
	xor bp,bp		; checksum accumulator
	xor ah,ah		; clear high byte for word add
	push cx
.checksum_loop:
	lodsb
	add bp,ax
	loop .checksum_loop
	pop cx			; CX = bytes_read

	; Send size word (big-endian)
	DPRINT sending_size_str
	mov ax,cx
	call write_word

	; Send checksum word (big-endian)
	DPRINT sending_checksum_str
	mov ax,bp
	call write_word

	; Send data bytes
	DPRINT sending_data_str
	mov byte [expected_ack], DATA_ACK
	mov si,PTR(block)
.send_data:
	lodsb
	call write_octet
	loop .send_data

	; Back to META_ACK for next chunk's size/checksum
	mov byte [expected_ack], META_ACK
	pop cx			; restore bytes_read
	cmp cx,BLOCK_SIZE
	je send_loop		; full block, more data to read

send_terminator:
	; Send size=0 to signal EOF
	xor ax,ax
	call write_word

	; Close file
	mov ah,0x3e		; DOS close file
	int 0x21		; BX = handle

	PRINT_SUCCESS sent_str
	mov ax,0x4c00		; DOS exit with errorlevel 0
	int 0x21

; Error exit.  DIE_IF jumps here when DEBUG == 0; debug builds go through
; print_err_and_exit instead.
exit:
	mov ax,0x4c01		; DOS exit with errorlevel 1
	int 0x21

; I/O routines
;
; For the following routines:
;
; dl = clock (0x00 or 0x10)
; al = output data, return values
; ax = word-sized arguments
;
; BX (file handle) is preserved across all calls.
;

; write_nibble: output nibble|clock to BASE_PORT
; Input: AL = data nibble, DL = clock (0x00 or 0x10)
write_nibble:
	and al,0x0f
	or al,dl
	push dx
	LOAD_BASE
	out dx,al
	pop dx
	ret

; write_ackd: write nibble, wait for reader ack
; Input: AL = data, DL = clock
; Output: AL = ack nibble
write_ackd:
	call write_nibble
	DO_WAIT_ACK
	ret

; write_octet: send byte as two nibbles (low first, high second)
; Input: AL = byte
; Preserves: BX, DX
write_octet:
	push dx
	push cx
	mov cl,al		; save byte
	and al,0x0f		; low nibble
	xor dl,dl		; clock = 0x00
	call write_ackd		; AL = ack_low
	mov ch,al		; save ack_low
	mov al,cl		; restore byte
	shr al,4		; high nibble
	mov dl,0x10		; clock = 0x10
	call write_ackd		; AL = ack_high
	; Check ACK type if expected_ack is set
	cmp byte [expected_ack], 0
	je .skip_ack_check
	cmp ch, byte [expected_ack]
	jne .ack_error
	cmp al, byte [expected_ack]
	jne .ack_error
.skip_ack_check:
	pop cx
	pop dx
	ret
.ack_error:
	pop cx
	pop dx
	mov dx, PTR(ack_err_str)
	mov ah, 0x09
	int 0x21
	mov ah, 0x4c
	mov al, 1
	int 0x21

; write_word: send 16-bit value big-endian (high byte first)
; Input: AX = word
; Preserves: BX, DX
write_word:
	push cx
	mov cl,al		; save low byte
	mov al,ah		; send high byte first
	call write_octet
	mov al,cl		; send low byte
	call write_octet
	pop cx
	ret

%if PORT_ARG
; parse_port: read an optional hex port address from the command line
;
; Input: ds:si -> command tail (CR-terminated)
; Output: [base_port] updated if an argument was given
; Clobbers: ax, cx, dx, si
;
; Any character below a space (CR, or the 0 that ppwrite leaves in place
; of it) ends the line.  Digits are not validated.
parse_port:
	lodsb
	cmp al,' '
	je parse_port			; skip leading spaces
	jb .done			; end of line: keep the default
	xor dx,dx
	mov cl,4
.digit:
	sub al,'0'			; '0'..'9' -> 0..9
	cmp al,10
	jb .have
	and al,0x1f			; 'A'..'F' and 'a'..'f' -> 0x11..0x16
	sub al,7			;   -> 10..15
.have:
	shl dx,cl
	or dl,al
	lodsb
	cmp al,' '
	ja .digit			; stop at space or end of line
	mov [base_port],dx
.done:
	ret
%endif ; PORT_ARG


%if (DEBUG > 1)

print_all_regs:
	push bp			; must preserve bp, but it doesn't
	push dx			;      get printed, though
	push cx
	push bx
	push ax
	call print_all
	pop ax
	pop bx
	pop cx
	pop dx
	pop bp
	ret

; Expect: dx, cx, bx, ax on stack
print_all:
	mov cx,4	; four registers
	mov bp,sp
print_loop:
	push cx
	mov ax,0xe05 + 'a' - 1

	sub al,cl
	int 0x10
	mov al,'x'
	int 0x10
	mov al,':'
	int 0x10
	add bp,2
	call print_hex
	call print_space
	pop cx
	loop print_loop
	ret

print_hex:
	push dx
	mov cx,4
	mov dx,[bp]
print_digit:
	rol dx,4
	mov ax,0x0e0f
	and al,dl
	add al,0x90
	daa
	adc al,0x40
	daa
	int 0x10
	loop print_digit
	pop dx
	ret

print_space:
	mov ax,0x0e20
	int 0x10
	ret

%endif ; (DEBUG > 1)

%if (DEBUG > 0)

print_nl:
	mov ax,0x0e0d
	int 0x10
	mov al,0xa
	int 0x10
	ret

print_err_and_exit:
	call print_info
	mov ax,0x4c01		; DOS exit with errorlevel 1
	int 0x21

print_info:
	push ax
	mov ah,0x09		; print string at ds:dx
	int 0x21
%if (DEBUG > 1)
	mov ah,0x0e
	mov al,':'
	int 0x10
	call print_space
	pop ax
	push ax
	call print_all_regs
%endif
	call print_nl
	pop ax
	ret

%endif ; (DEBUG > 0)

; String constants
magic_str:		db 'ppcopy'

sent_str:
%if (DEBUG > 0)
			db 'sent$'
%else
			db 'sent',10,13,'$'
%endif

usage_str:		db 'usage: ppwrite <file>',10,13,'$'

%if (DEBUG > 0)
open_err_str:		db 'open$'
read_err_str:		db 'read$'

%if (DEBUG > 1)
sending_size_str:	db 'sending size$'
sending_checksum_str:	db 'sending checksum$'
sending_data_str:	db 'sending data$'
%endif ; (DEBUG > 1)

%endif ; (DEBUG > 0)


expected_ack:		db 0
%if PORT_ARG
base_port:		dw BASE_PORT
%endif
ack_err_str:		db 'error: unexpected ACK type',13,10,'$'

	absolute 0x100 + $-start + 10	; for 256 bytes PSP + code-size + safety
block:			resw 1 ; expands to fill rest of 64k block
