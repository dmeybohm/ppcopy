;
; parread.nasm -- Copy files through through a parallel port connected
;                   with a laplink cable in DOS/DOSEMU/FreeDOS 
;                 Top speed may be ~14k/sec. 
;
%define BASE_PORT	0x378
%define DATA_PORT	(BASE_PORT+1)
%define CONTROL_PORT	(BASE_PORT+2)
%define OUTPUT_FILE	'C:\parread.out'

%define DATA_ACK	0x2
%define START_MAGIC	0xd7

;
; Turn these off for smaller code,
;   on for more verbosity/safety.
;
%ifndef DEBUG
%define DEBUG		0	; 0, 1, or 2 (can be overridden from command line)
%endif
%define CLOSE_FILE	0

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

	org 0x100

;
; This is the main routine.
;
; It copies chunks, sized < 64k, of a file at a time.  
; Chunk sizes too close to 64k will cause unpredictable errors.  
;
; This could be fixed, but as its a borderline case 
;     (62k should be fine), and as it doesn't really prevent 
;     large files from being transfered, fixing it is probably not worth 
;     the added time/complexity.
;
start:
	mov dx,PTR(output_file)
	mov ah,0x3c 			; DOS create file interrupt
	xor cx,cx 			; attrib-flags
	int 0x21
	DIE_IF c,SYM(open_err_str)
	mov bx,ax			; Store file-ptr in bx
	cld

	call read_octet
	cmp al,START_MAGIC
	DIE_IF ne,SYM(no_synch_str)

start_read:
	mov di,PTR(block)		 ; where the data is stored
	mov si,di

recv_size:
	call read_word
	mov cx,ax			; remember to preserve size in cx
	jcxz close_file
	DPRINT size_str 

recv_checksum:
	DPRINT synch_str 
	call read_word
	mov bp,ax			; store checksum in bp
	DPRINT checksum_str 

recv_data:
	PRINT_INFO reading_data_str 
	push cx
.repeat:
	call read_octet
	stosb
	loop .repeat
	pop cx

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
	sub cx,ax
	jnz write_file			; keep going if anything left to write
	JMP_IF z,SYM(start_read)	; smaller than absolute jmp
	DPRINT not_restarting_str

%if CLOSE_FILE == 1
close_file:
	mov ah,0x3e			; bx still contains file handle
	int 0x21			; DOS close file handle fn
	DIE_IF c,SYM(close_err_str)
	PRINT_SUCCESS wrote_str 
exit:
	int 0x20
%else
close_file:
exit:
	PRINT_SUCCESS wrote_str 
	mov ah,0x4c			; DOS exit fn 
	int 0x21 			;   with return code in %al
%endif


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

; This routine is useless.  it should be inlined instead
;; in=(al = data, dx = clock)
write_ack:
	push dx
	shr dl,3
	mov al,DATA_ACK
	or al,dl
	mov dx,BASE_PORT
	out dx,al
	pop dx
	ret

%macro DO_READ 0 ;(dl = clock, al = output)
;read_noack: 
	push cx
	push bx
	mov bx,dx	; clock aliased to bl
	mov dx,DATA_PORT
.redo:
	in al,dx
	mov cl,al	; cl = first value read
	uSLEEP
	and al,0x80
	xor al,bl
	jz .redo
	in al,dx
	cmp al,cl
	jne .redo

	shr al,3
	and al,0x0f
	mov dx,bx	; restore dx from bx
	pop bx
	pop cx
	;ret
%endmacro
	
read_status: ;(dx = clock)
	;call read_noack
	DO_READ
	push ax
	call write_ack
	pop ax
	ret

read_octet: ;(ax = ack)
	push dx
	push cx
	xor dx,dx
	call read_status
	mov cl,al	; save low nibble
	mov dl,0x80	; make clock go high
	call read_status
	shl al,4	; put high nibble in high al
	or al,cl
	pop cx
	pop dx
	ret

read_word:
;	push cx
;	call read_octet
;	mov cx,ax
;	call read_octet
;	shl ax,8
;	or ax,cx
;	pop cx
;	ret
	call read_octet			; Big endian read here
	mov ah,al			;   saves the xchg instruction.
	call read_octet
	;xchg ah,al
	ret

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

wrote_str:		db 'wrote ', ; ``fallthrough''
output_file:		db OUTPUT_FILE,0
%if (DEBUG > 0)        
                        db '$'
%else
			db 10,13,'$' ; no crlf printing code unless debug
%endif
			
%if (DEBUG > 0)
; Strings printed by DIE_IF
open_err_str:		db 'open','$'
no_synch_str:		db 'no synch','$'
reading_data_str:	db 'reading','$'
checksum_err_str:	db 'bad checksum','$'
write_err_str:		db 'write','$'
close_err_str:		db 'close','$'

%if (DEBUG > 1)
; Strings printed by DPRINT
checksum_str:		db 'read checksum','$'
size_str:		db 'read size','$'
reading_low_data:	db 'reading low data','$'
reading_high_data:	db 'reading high data','$'
writing_str:		db 'calling write','$'
good_checksum_str:	db 'good checksum','$'
synch_str:		db 'got synch','$'
waiting_str:		db 'waiting for data','$'
not_restarting_str:	db 'not restarting read loop','$'
%endif ;(DEBUG > 1)

%endif; (DEBUG > 0)


	absolute 0x100 + $-start + 10	; for 256 bytes PSP + code-size + safety
block:			resw 1 ; expands to fill rest of 64k block
