; IO.ASM - SD-DOS I/O system
org 0x1000
bits 16

start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov [boot_drive], dl

    ; Read first root directory sector
    ; LBA 19 = CHS 0/1/2
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov dh, 1
    mov cl, 2
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    ; Search 16 directory entries
    mov di, 0x0500
    mov cx, 16

search:
    push cx
    push di

    mov si, sddos_name
    mov cx, 11
    repe cmpsb

    pop di
    pop cx

    je found

    add di, 32
	loop search

    jmp error

found:
    ; Get starting cluster
    mov ax, [di+26]

    ; cluster -> LBA
    ; cluster 2 = LBA 33
    sub ax, 2
    add ax, 33

    ; LBA -> CHS
    xor dx, dx
    mov bx, 18
    div bx

    inc dl
    mov cl, dl

    xor dx, dx
    mov bx, 2
    div bx

    mov ch, al
    mov dh, dl

    ; Load SDDOS.SYS at 0000:2000
    xor ax, ax
    mov es, ax
    mov bx, 0x2000

    mov ah, 0x02
    mov al, 1
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    jmp 0x0000:0x2000

disk_error:
error:
    mov ah, 0x0E
    mov al, 'E'
    int 0x10

hang:
    jmp hang

boot_drive:
    db 0

sddos_name:
    db 'SDDOS'
    times 3 db ' '
    db 'SYS'