	org 0x100

	mov ax,0x10
	mov dx,0x378
	out dx,al

	mov ax,0x4c00
	int 0x21

	times 20 db 0	; freedos won't load .com files smaller than 
	                ; 28 bytes 
