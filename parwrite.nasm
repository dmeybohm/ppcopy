;
; parwrite.nasm -- Send files through a parallel port connected
;                  with a laplink cable from DOS/DOSEMU/FreeDOS
;

%define BASE_PORT	0x378
%define DATA_PORT	(BASE_PORT+1)
%define CONTROL_PORT	(BASE_PORT+2)

%define BLOCK_SIZE	32768

;
; Turn these off for smaller code,
;   on for more verbosity/safety.
;
%ifndef DEBUG
%define DEBUG		0	; 0, 1, or 2 (can be overridden from command line)
%endif

;
; This might make for more correct operation,
; but it makes the transfer so slow that
; it's not worth doing
;
;%define uSLEEP		out 0x80,al
%define uSLEEP

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
	mov dx,DATA_PORT
%%redo:
	in al,dx		; read raw from status port
	mov cl,al		; save raw for stability check
	uSLEEP
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
	mov ax,0x81		; start with 0xb8 so file(1) detects COM
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
	int 0x20
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

	; Open file for reading
	mov ah,0x3d		; DOS open file
	mov al,0x00		; read-only
	int 0x21
	DIE_IF c,SYM(open_err_str)
	mov bx,ax		; BX = file handle (preserved throughout)

	; Initialize port
	push dx
	mov dx,BASE_PORT
	xor al,al
	out dx,al
	pop dx

	; Send padding byte (absorbs nibble desync if reader starts first)
	xor al,al
	call write_octet

	; Send "ppcopy" start sequence
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
	mov si,PTR(block)
.send_data:
	lodsb
	call write_octet
	loop .send_data

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

exit:
	mov ah,0x4c		; DOS exit fn
	int 0x21		;   with return code in %al

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
	mov dx,BASE_PORT
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
; Output: ZF=1 if acks match (success)
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
	cmp al,ch		; compare acks (sets ZF)
	pop cx
	pop dx
	ret

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
no_reg:
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
	int 0x20		; DOS terminate fn

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

usage_str:		db 'usage: parwrite <file>',10,13,'$'

%if (DEBUG > 0)
open_err_str:		db 'open$'
read_err_str:		db 'read$'

%if (DEBUG > 1)
sending_size_str:	db 'sending size$'
sending_checksum_str:	db 'sending checksum$'
sending_data_str:	db 'sending data$'
%endif ; (DEBUG > 1)

%endif ; (DEBUG > 0)


	absolute 0x100 + $-start + 10	; for 256 bytes PSP + code-size + safety
block:			resw 1 ; expands to fill rest of 64k block
