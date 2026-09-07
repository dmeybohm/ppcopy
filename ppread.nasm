;
; ppread.nasm -- Copy files through through a parallel port connected
;                   with a laplink cable in DOS/DOSEMU/FreeDOS
;                 Top speed may be ~14k/sec.
;
; Received data is written to stdout (DOS handle 1), so redirect it:
;
;	ppread > file
;
; An optional hex base address selects a parallel port other than 0x378:
;
;	ppread 278 > file
;
%define BASE_PORT	0x378
%define DATA_PORT	(BASE_PORT+1)
%define STDOUT		1
%define CMD_TAIL	0x81		; command line in the PSP, CR-terminated

%define META_ACK	0x1

;
; Turn these off for smaller code,
;   on for more verbosity/safety.
;
%ifndef DEBUG
%define DEBUG		0	; 0, 1, or 2 (can be overridden from command line)
%endif
%define CLOSE_FILE	1

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
; Use conditional jcc if not debuging, and absolute
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

	org 0x100

;
; This is the main routine.
;
; It copies chunks of a file at a time.  Chunk sizes are treated as
; signed 16-bit values; sizes <= 0 signal end of transfer.  Max chunk
; size is 32,767 bytes.
;
start:
	mov ax,STDOUT			; start with 0xb8 so file(1) detects COM
	xchg bx,ax			; output handle, kept in bx throughout
	cld

%if PORT_ARG
	mov si,CMD_TAIL
	call parse_port
%endif

	; Initialize port so writer sees a known state
	LOAD_BASE
	mov al,0x10
	out dx,al

	; Scan for "ppcopy" using scasb prefix matcher
	mov di,PTR(magic_str)
.scan_magic:
	call read_octet
	scasb				; cmp al,[es:di]; inc di
	je .check_done
	mov di,PTR(magic_str)
	cmp al,'p'
	jne .scan_magic
	inc di				; matched pattern[0]='p'
	inc di				; matched pattern[1]='p' too
	jmp .scan_magic
.check_done:
	cmp byte [di],META_ACK		; sentinel: current_ack follows magic_str
	jne .scan_magic

start_read:
	mov di,PTR(block)		 ; where the data is stored
	mov si,di

recv_size:
	call read_word
	xchg cx,ax			; remember to preserve size in cx
	test cx,cx
	jle close_file
	DPRINT size_str

recv_checksum:
	DPRINT synch_str
	call read_word
	xchg bp,ax			; store checksum in bp
	DPRINT checksum_str

recv_data:
	PRINT_INFO reading_data_str
	inc byte [current_ack]
	push cx
.repeat:
	call read_octet
	stosb
	loop .repeat
	pop cx
	dec byte [current_ack]

do_checksum:
	xor ax,ax
	push cx
.sum_loop:
	lodsb
	sub bp,ax			; bp holds checksum received
	loop .sum_loop			; loop won't trash zero flag from sub
	DIE_IF nz,SYM(checksum_err_str) 
	pop cx
	DPRINT good_checksum_str 

write_file:
	DPRINT writing_str
	mov dx,block			; ds:dx points to block to write
	mov ah,0x40			; DOS write-block function
	int 0x21			; bx stills hold file-handle
	DIE_IF c,SYM(write_err_str)	; a set carry-flag indicates error
	cmp ax,cx			; DOS only writes short when the disk
	DIE_IF ne,SYM(write_err_str)	;   is full, and reports that with
					;   carry clear, so treat it as fatal
	JMP_IF z,SYM(start_read)	; smaller than absolute jmp
	DPRINT not_restarting_str

%if CLOSE_FILE == 1
close_file:
	mov ah,0x3e			; bx still contains file handle
	int 0x21			; DOS close file handle fn: flushes
	DIE_IF c,SYM(close_err_str)	;   and updates the directory entry
					;   even though COMMAND.COM still holds
					;   a reference to a redirected stdout
%else
close_file:				; DOS closes the handle on exit, but
%endif					;   any error doing so goes unreported
	mov ax,0x4c00			; DOS exit with errorlevel 0
	int 0x21

; Error exit.  DIE_IF jumps here when DEBUG == 0; debug builds go through
; print_err_and_exit instead.
exit:
	mov ax,0x4c01			; DOS exit with errorlevel 1
	int 0x21


; For the following routines:
;
; dl = clock
; cl = count/size, temporary values
; al = input data, return values
; ax = word-sized return values
;
; clock must be 0x80 or 0x00
;
; Maybe these routines could be slightly restructured to
; reduce code size.  
;

%macro DO_READ 0 ;(dl = clock, al = output)
	push cx
	mov ch,dl	; clock aliased to ch
	LOAD_STATUS
.redo:
	in al,dx
	mov cl,al	; cl = first value read
	and al,0x80
	xor al,ch
	jz .redo
	in al,dx
	cmp al,cl
	jne .redo

	shr al,3
	and al,0x0f
	mov dl,ch	; restore dl from ch
	pop cx
%endmacro

read_status: ;(dx = clock)
	DO_READ
	push ax
	shr dl,3
	mov al,[current_ack]
	or al,dl
	LOAD_BASE
	out dx,al
	pop ax
	ret

read_octet: ;(ax = ack)
	push dx
	xor dx,dx
	call read_status
	push ax		; save low nibble on stack
	mov dl,0x80	; make clock go high
	call read_status
	shl al,4	; put high nibble in high al
	pop dx
	or al,dl	; combine with low nibble
	pop dx
	ret

read_word:
	call read_octet			; Big endian read here
	mov ah,al			;   saves the xchg instruction.
	call read_octet
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
	push bp				; must preserve bp, but it doesn't
	push dx				;      get printed, though
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
	mov ax,0x4c01		; DOS exit with errorlevel 1
	int 0x21

; Print the '$'-terminated string at ds:dx to the console.  Uses int 0x29
; (fast console output) rather than int 0x21/ah=0x09 so that debug output
; goes to the screen instead of into a redirected stdout.
print_info:
	push ax
	push si
	mov si,dx
.next:
	lodsb
	cmp al,'$'
	je .done
	int 0x29
	jmp .next
.done:
	pop si
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

%if (DEBUG > 0)
; Strings printed by DIE_IF
reading_data_str:	db 'reading','$'
checksum_err_str:	db 'bad checksum','$'
write_err_str:		db 'write','$'
close_err_str:		db 'close','$'

%if (DEBUG > 1)
; Strings printed by DPRINT
checksum_str:		db 'read checksum','$'
size_str:		db 'read size','$'
writing_str:		db 'calling write','$'
good_checksum_str:	db 'good checksum','$'
synch_str:		db 'got synch','$'
not_restarting_str:	db 'not restarting read loop','$'
%endif ;(DEBUG > 1)

%endif; (DEBUG > 0)


magic_str:		db 'ppcopy'
current_ack:		db META_ACK	; must follow magic_str (sentinel for scan)
%if PORT_ARG
base_port:		dw BASE_PORT
%endif

	absolute 0x100 + $-start + 10	; for 256 bytes PSP + code-size + safety
block:			resw 1 ; expands to fill rest of 64k block
