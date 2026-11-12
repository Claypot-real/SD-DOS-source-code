; SDDOS.ASM
; SD-DOS 1.25 system kernel

org 0x2000
bits 16

start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Blank line before boot message
	call crlf
	
	mov si, msg_version
    call print_string
	call crlf
	
    mov si, msg_copyright
    call print_string
	call crlf
	call crlf

    ; Read first root directory sector
    mov bx, 0x1800

	mov ah, 0x02
	mov al, 1
    mov ch, 0
    mov dh, 1
    mov cl, 2
    mov dl, 0
    int 0x13
    jc disk_error

    ; Search 16 directory entries
    mov di, 0x1800
    mov cx, 16

search_command:
    push cx
    push di

    mov si, command_name
    mov cx, 11
    repe cmpsb

    pop di
    pop cx

    je command_found

    add di, 32
    loop search_command

    jmp disk_error

command_found:
    ; Get starting cluster
    mov ax, [di+26]
	mov [current_cluster], ax

    ; -----------------------------
    ; Load FAT #1
    ; LBA 1-9 = CHS 0/0/2
    ; Buffer = 0000:0500
    ; -----------------------------
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 9
	mov ch, 0
	mov cl, 2
	mov dh, 0
    mov dl, 0
    int 0x13
    jc disk_error

    ; COMMAND.COM destination
	mov bx, 0x3000

load_cluster:
    mov ax, [current_cluster]

	; -----------------------------
    ; Cluster -> LBA
    ;
    ; cluster 2 = LBA 33
    ; LBA = cluster - 2 + 33
    ; -----------------------------
    sub ax, 2
    add ax, 33

    ; -----------------------------
    ; LBA -> CHS
    ; 18 sectors/track
    ; 2 heads
    ; -----------------------------
    xor dx, dx
    mov si, 18
    div si

    inc dl
    mov cl, dl

    xor dx, dx
    mov si, 2
    div si

    mov ch, al
    mov dh, dl

    ; -----------------------------
    ; Read cluster into ES:BX
    ; -----------------------------
    push bx

    xor ax, ax
    mov es, ax

    pop bx

    mov ah, 0x02
    mov al, 1
    mov dl, 0
    int 0x13
    jc disk_error

    ; Next destination
    add bx, 512

    ; -----------------------------
    ; Get next FAT12 cluster
    ; offset = cluster + cluster/2
    ; -----------------------------
    mov ax, [current_cluster]
    mov dx, ax

    shr ax, 1
    add ax, dx

    mov si, 0x0500
    add si, ax

    mov ax, [si]

    test dx, 1
    jz even_cluster

    ; Odd cluster
    shr ax, 4
    jmp cluster_ready

    even_cluster:
    and ax, 0x0FFF

    cluster_ready:
    ; AX = next cluster

    cmp ax, 0x0FF8
    jae launch_command

    mov [current_cluster], ax
    jmp load_cluster


;-----------------------------
; Launch COMMAND.COM
; -----------------------------
launch_command:
    jmp 0x0000:0x3000


; -----------------------------
; Error
; -----------------------------
disk_error:
    mov si, msg_error
	call print_string

hang:
    jmp hang


; -----------------------------
; Print string
; -----------------------------
print_string:
    mov ah, 0x0E

.next:
    lodsb
    test al, al
    jz .done

    int 0x10
    jmp .next

.done:
    ret


; -----------------------------
; CRLF
; -----------------------------
crlf:
    mov ah, 0x0E
	
    mov al, 0x0D
    int 0x10
	
    mov al, 0x0A
    int 0x10
	
    ret


; -----------------------------
; Data
; -----------------------------
command_name:
    db 'COMMAND COM'

current_cluster:
    dw 0

msg_version:
    db 'SD-DOS version 1.25', 0

msg_copyright:
    db 'Copyright 2026 Sawdust, Inc.',0

msg_error:
    db 'Disk error',0