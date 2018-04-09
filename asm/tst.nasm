	org 0x100
	xor ax,ax
	or ax,ax
	mov ax,1
	jz print_yes
print_no:
	mov dx,print_no_str
	jmp print_it
print_yes:
	mov dx,print_yes_str

print_it:
	mov ah,0x09
	int 0x21
	int 0x20
	

print_yes_str: db 'Yes, it was equal','$'
print_no_str:  db 'No, it was not equal','$'

