BITS 16

os_call_vectors:
	jmp os_main			

os_main:
	cli				
	mov ax, 0
	mov ss, ax			
	mov sp, 0FFFFh
	sti				
	cld				
					
	mov ax, 2000h			
	mov ds, ax			
	mov es, ax			
	mov fs, ax
	mov gs, ax

	mov ax, 1003h			
	mov bx, 0			
	int 10h

	
load_menu:
	mov si , option1


Print:
	lodsb					
	or			al, al		
	jz			PrintDone	
	mov			ah,	0eh	
	int			10h
	jmp			Print		
PrintDone:
	ret					



option1	db "This is 16-bit kernel mode" , 0	  

	
