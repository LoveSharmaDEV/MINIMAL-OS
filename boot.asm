BITS 16                        
jmp short bootloader_start ; jmp instruction used here is a 3 byte instruction , it takes (0th, 1st and 2nd Byte)
nop				


; FAT12 File system 

OEM      		db "operatin"	; 3rd, 4th, 5th, 6th, 7th, 8th, 9th, 10th bytes total= 8 bytes
BytesPSector		dw 512		; 11th and 12th bytes total= 2 bytes
SectorsPCluster	        db 1		; 13th byte total= 1 byte
ReservedForBoot		dw 1		; 14th and 15th byte total= 2 bytes
NumberOfFats		db 2		; 16th byte total= 1 byte
RootDirEntries		dw 224		; 17th and 18th byte total= 2 bytes
LogicalSectors		dw 2880		; 19th byte and 20th byte total= 2 bytes
MediumByte		db 0F0h		; 21st byte total= 1 byte
SectorsPerFat		dw 9		; 22nd and 23rd byte total= 2 bytes
SectorsPerTrack		dw 18		; 24th and 25th byte total= 2 bytes
Sides			dw 2		; 26th and 27th byte total= 2 bytes
HiddenSectors		dd 0		; 28th, 29th, 30th, 31st total= 4 bytes
LargeSectors		dd 0		; 32nd, 33rd, 34th, 35th total= 4 bytes
DriveNo			dw 0		; 36th byte total= 1 byte and  37th byte for current head total= 1 byte
Signature		db 41		; 38th byte total= 1 byte
VolumeID		dd 00000000h	; 39th, 40th, 41st, 42nd total= 4 bytes
VolumeLabel		db "DEVOPSOS   "; [43rd, 53rd byte] total= 11 bytes  
FileSystem		db "FAT12   "	; [54th, 61st byte] total= 8 bytes

; From th 62nd byte onwards our main bootstrap code begins to execute


begin_bootloader:
	mov ax, 07C0h			; 07C0h when shifted left by 4 bits give 0x7C000, this is the place where bootloader is loaded inside th main memory.
	add ax, 544			; We want a buffer of 8k along with 512 bytes for bootloader. That would exactly need 544 paragraphs.	
	cli				; Working with stack	
	mov ss, ax                       ; We have now ss = 07C0h + 544 . SS register when refers main memory it 16 bits of address is converted in 20 bits, That means 4 bit left shift happens.	
	mov sp, 4096                     ; A 4k stack space is created
	sti				
	mov ax, 07C0h			; Set ax at the start of memory
	mov ds, ax                       ; Here si where the 07C0h is shifted left by 4 bits, so that a 20  it address can be generated.
	mov byte [bootdev], dl		; Save boot device number


drive_check:				
	mov ax, 19			; 19 sector is the LBA of the root directory. It is present from here till next 14 directories.
	call lbatochs                      
	mov si, buffer			
	mov bx, ds
	mov es, bx
	mov bx, si                      ; Now we ES:BX pointing to our buffer
	mov ah, 2			; Params for int 13h: read floppy sectors
	mov al, 14			; al register stores the number of sectors we have to read
	pusha				; pusha stores all general purpose registers into the stack in order AX , CX , DX , BX , SP , BP , SI , DI


read_14_sectors:
	popa				; In case registers are altered by int 13h
	push
	int 13h				; Read sectors using BIOS
	jnc find_kernel_start		; If read went OK, skip ahead
	call reset_floppy		; Otherwise, reset floppy controller and try again
	jnc read_14_sectors		; Floppy reset OK?
	jmp reboot			; If not, fatal double error


find_kernel_start:
	popa
	mov ax, ds			; Now are root directory is inside buffer , here we are pointing es:di to buffer , for string operations
	mov es, ax			; 
	mov di, buffer
	mov cx, word [RootDirEntries]	; Search all 224 entries
	mov ax, 0			; Searching at offset 0


find_kernel_file:
	xchg cx, dx			; Swapping cx with dx , because we have to use cx for string byte comparison. We will restore this DX later once the string is compared.
	mov si, kern_filename		; Start searching for kernel filename , which is of 11 byte , 8 bytes for file name and 3 bytes for extension
	mov cx, 11                       ; Initializing counter to 11 for comparison
	rep cmpsb                        ; loop starts
	je kernel_file_found		; Here we have to keep in mind that at this time our offset is at 11.
	add ax, 32			; If file name not matched , we have to move to next 32 byte entry.
	mov di, buffer			; Point to next entry
	add di, ax
	xchg dx, cx			; Get the original CX back
	loop find_kernel_file
	mov si, file_not_found		; If kernel is not found quit
	call print_string
	jmp reboot


kernel_file_found:			
	mov ax, word [es:di+0Fh]	; here we fetch the logical cluster value for first cluster in data area that contains file content
	mov word [cluster], ax
	mov ax, 1			; Sector 1 = first sector of first FAT
	call lbatochs
	mov di, buffer			; ES:BX points to our buffer once again.
	mov bx, di
	mov ah, 2			; int 13h params: read (FAT) sectors
	mov al, 9			; All 9 sectors of 1st FAT
	pusha			


read_kernel:
	popa				; In case registers are altered by int 13h
	pusha
	stc
	int 13h				; Read sectors using the BIOS
	jnc read_fat_ok			; If read went OK, skip ahead
	call reset_floppy		; Otherwise, reset floppy controller and try again
	jnc read_kernel			; Floppy reset OK?
	mov si, disk_error		; If not, print error message and reboot
	call print_string
	jmp reboot			; Fatal double error


read_fat_table:
	popa
	mov ax, 2000h			; Segment where we'll load the kernel
	mov es, ax
	mov bx, 0
	mov ah, 2			; int 13h floppy read params
	mov al, 1
	push ax				; Save in case we (or int calls) lose it

load_kernel_sector:
	mov ax, word [cluster]		; Convert sector to logical
	add ax, 31
	call lbatochs		; converting logical sector into CHS address form
	mov ax, 2000h			; Set buffer past what we've already read
	mov es, ax
	mov bx, word [pointer]          ; we are using a pointer variable because we will be reading kernel cluster 512 byte each
	pop ax			        ; Save in case we lose it
	push ax
	stc
	int 13h
	jnc use_fat_table	        ; If there's no error...
	call reset_floppy		; Otherwise, reset floppy and retry
	jmp load_file_sector

use_fat_table:
	mov ax, [cluster]
	mov dx, 0
	mov bx, 3
	mul bx
	mov bx, 2
	div bx				; DX = [cluster] mod 2
	mov si, buffer
	add si, ax			; AX = word in FAT for the 12 bit entry
	mov ax, word [ds:si]

	or dx, dx			; If DX = 0 [cluster] is even; if DX = 1 then it's odd

	jz even_entry			; If [cluster] is even, drop last 4 bits of word
					; with next cluster; if odd, drop first 4 bits

odd_entry:
	shr ax, 4			; Shift out first 4 bits (they belong to another entry)
	jmp short next_cluster_cont


even_entry:
	and ax, 0FFFh			; Mask out final 4 bits


continue_cluster-chain:
	mov word [cluster], ax		; Store cluster
	cmp ax, 0FF8h			; FF8h = end of file marker in FAT12
	jae end
	add word [pointer], 512		; Increase buffer pointer 1 sector length
	jmp load_kernel_sector


end:					; We've got the file to load!
	pop ax				; Clean up the stack (AX was pushed earlier)
	mov dl, byte [bootdev]		; Provide kernel with boot device info
	jmp 2000h:0000h			; Jump to entry point of loaded kernel!


; BOOTLOADER SUBROUTINES

reboot:
	mov ax, 0
	int 16h				; Wait for keystroke
	mov ax, 0
	int 19h				; Reboot the system


print_string:				; Output string in SI to screen
	pusha

	mov ah, 0Eh			; int 10h function

.repeat:
	lodsb				; Get char from string
	cmp al, 0
	je .done			; If char is zero, end of string
	int 10h				; Otherwise, print it
	jmp short .repeat

.done:
	popa
	ret


reset_floppy:		; IN: [bootdev] = boot device; OUT: carry set on error
	push ax
	push dx
	mov ax, 0
	mov dl, byte [bootdev]
	stc
	int 13h
	pop dx
	pop ax
	ret


lbatochs:			; Calculate head, track and sector settings for int 13h			
                                 ; IN: logical sector in AX, OUT: correct registers for int 13h
	push bx
	push ax
	mov bx, ax			; Save logical sector
	mov dx, 0			; First the sector
	div word [SectorsPerTrack]
	add dl, 01h			; Physical sectors start at 1
	mov cl, dl			; Sectors belong in CL for int 13h
	mov ax, bx
	mov dx, 0			; Now calculate the head
	div word [SectorsPerTrack]
	mov dx, 0
	div word [Sides]
	mov dh, dl			; Head/side
	mov ch, al			; Track
	pop ax
	pop bx
	mov dl, byte [bootdev]		; Set correct device
	ret


; CONSTANTS AND VARIABLES

	kern_filename	db "KERNEL  BIN"	; kernel filename
	disk_error	db "Floppy error! Press any key...", 0
	file_not_found	db "KERNEL.BIN not found!", 0
	bootdev		db 0 	; Boot device number
	cluster		dw 0 	; Cluster of the file we want to load
	pointer		dw 0 	; Pointer into Buffer, for loading kernel


;END OF BOOT SECTOR

	times 510-($-$$) db 0	; Pad remainder of boot sector with zeros
	dw 0AA55h		; Boot signature (DO NOT CHANGE!)


buffer:				; 8192 bytes of buffer
