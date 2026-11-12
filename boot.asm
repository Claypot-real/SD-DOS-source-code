org 0x7C00
bits 16

jmp short start
nop

; FAT12 BPB
db 'SDDOS1.2'
dw 512
db 1
dw 1
db 2
dw 224
dw 2880
db 0xF0
dw 9
dw 18
dw 2
dd 0
dd 0

start:
cli
xor ax, ax
mov ds, ax
mov es, ax
mov ss, ax
mov sp, 0x7C00
sti

mov [boot_drive], dl

; Root directory starts at LBA 19
; LBA 19 = CHS cylinder 0, head 1, sector 2

mov bx, 0x0500

mov ah, 0x02
mov al, 1
mov ch, 0
mov dh, 1
mov cl, 2
mov dl, [boot_drive]
int 0x13
jc disk_error

; Search 16 entries in this 512-byte sector
mov di, 0x0500
mov cx, 16

search_entry:
push cx
push di

mov si, io_filename
mov cx, 11
repe cmpsb

pop di
pop cx

je found

add di, 32
loop search_entry

not_found:
mov al, 'N'
jmp print_result

found:
    ; DI still points to the IO.SYS directory entry

    ; Get starting cluster from bytes 26-27
    mov ax, [di+26]
    
    ; Convert cluster -> LBA
    ; First data sector = 33
    ; Cluster 2 = LBA 33
    sub ax, 2
    add ax, 33
    
    ; For our current disk IO.SYS is one cluster,
    ; so read one sector.

    ; AX now contains the LBA.
    ; Our floppy has 18 sectors/track, 2 heads.

    xor dx, dx
    mov bx, 18
    div bx ; AX = track/head index, DX = sector offset

    inc dl ; sector numbers start at 1
    mov cl, dl
 
    xor dx, dx
    mov bx, 2
    div bx ; AX = cylinder, DX = head

    mov ch, al
    mov dh, dl
   
    ; Destination = 0000:1000
    xor ax, ax
    mov es, ax
    mov bx, 0x1000
  
    mov ah, 0x02
    mov al, 1
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    jmp 0x0000:0x1000

print_result:
mov ah, 0x0E
int 0x10

hang:
jmp hang

disk_error:
mov al, 'E'
mov ah, 0x0E
int 0x10
jmp hang

boot_drive:
db 0

io_filename:
db 'IO'
times 6 db ' '
db 'SYS'

times 510-($-$$) db 0
dw 0xAA55