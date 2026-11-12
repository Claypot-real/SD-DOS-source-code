; COMMAND.ASM - SD-DOS command interpreter

org 0x3000
bits 16

start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Detect floppy drives

    mov si, banner
    call print_string
    call crlf

main_loop:
    call print_prompt

    mov di, input_buffer
	call read_line
	
	; Empty command?
	mov si, input_buffer
	lodsb
	test al, al
	jz .next
	
	; Check commands
    mov si, input_buffer

    ; -----------------------------
    ; Drive change: X:
    ; -----------------------------
    cmp byte [si+1], ':'
    jne .check_dir

    cmp byte [si+2], 0
    jne .check_dir

    mov al, [si]

    cmp al, 'A'
    jb .invalid_drive

    cmp al, 'Z'
    ja .invalid_drive

    ; Convert A-Z to BIOS drive number
    sub al, 'A'
    mov dl, al

    ; Try resetting requested floppy drive
    xor ah, ah
    int 0x13
    jc .invalid_drive

    ; Drive worked, make it current
    mov [current_drive], dl
    jmp .next


.invalid_drive:
    call crlf

    mov si, msg_invalid_drive
    call print_string

    jmp .next


.check_dir:
    cmp byte [si], 'D'
    jne .check_copy
    cmp byte [si+1], 'I'
    jne .check_copy
    cmp byte [si+2], 'R'
    jne .check_copy
    cmp byte [si+3], 0
    jne .check_copy

    call crlf
    call cmd_dir
    jmp .next

.check_copy:
    cmp byte [si], 'C'
    jne .check_rem
    cmp byte [si+1], 'O'
    jne .check_rem
    cmp byte [si+2], 'P'
    jne .check_rem
    cmp byte [si+3], 'Y'
    jne .check_rem
	
	; COPY by itself?
	cmp byte [si+4], 0
	jne .copy_has_args
	
	call crlf
	mov si, msg_zero_copied
	call print_string
	jmp .next

.copy_has_args:
    ; Require a space after COPY
	cmp byte [si+4], ' '
	jne .check_rem

    ; Default both sides to current drive
    mov al, [current_drive]
    mov [copy_source_drive], al
    mov [copy_dest_drive], al

	; Source begins after "COPY"
	add si, 5

	; Optional source drive prefix: A:, B:, etc.
    cmp byte [si+1], ':'
    jne .source_drive_done

    mov al, [si]

    cmp al, 'A'
    jb .bad
    cmp al, 'Z'
    ja .bad

    sub al, 'A'
    mov [copy_source_drive], al

    ; Skip "A:"
    add si, 2

.source_drive_done:
	mov di, copy_source
	call parse_filename

    ; SI should now point at the space before destination
	cmp byte [si], ' '
	jne .missing_destination

.skip_spaces:
    inc si
	cmp byte [si], ' '
	je .skip_spaces

    cmp byte [si], 0
	je .missing_destination

    ; Parse destination
	; Optional destination drive prefix
    cmp byte [si+1], ':'
    jne .dest_drive_done

    mov al, [si]

    cmp al, 'A'
    jb .bad
    cmp al, 'Z'
    ja .bad

    sub al, 'A'
    mov [copy_dest_drive], al

    ; Skip "B:"
    add si, 2

.dest_drive_done:

	; Destination is only a drive? (A: or B:)
	cmp byte [si], 0
	jne .parse_dest_name

    ; Copy source 8.3 name to destination
	mov si, copy_source
	mov di, copy_dest
	mov cx, 11
	rep movsb

    jmp .dest_name_done

.parse_dest_name:
	mov di, copy_dest
	call parse_filename

.dest_name_done:
	call crlf

	; COPY *.* ?
	cmp byte [copy_source], '*'
	jne .normal_copy

	cmp byte [copy_source+8], '*'
	jne .normal_copy

	call copy_all_files
	jmp .next

.normal_copy:

	call find_copy_source
	jc .copy_not_found

	call find_copy_dest
	jnc .copy_dest_exists

    ; Destination doesn't exist.
    ; Find somewhere for its directory entry.
	call find_free_dir_entry
    jc .copy_directory_full

    call find_free_cluster
    jc .copy_disk_full

    ; First COPY implementation supports one cluster
    call perform_multicluster_copy
	jc .copy_failed

    mov si, msg_copy_done
    call print_string
    jmp .next

.copy_failed:
    mov si, msg_disk_error
    call print_string
    jmp .next


.copy_disk_full:
    mov si, msg_disk_full
    call print_string
    jmp .next


.copy_directory_full:
    mov si, msg_directory_full
    call print_string
    jmp .next
	
	
.copy_not_found:
    mov si, msg_zero_copied
	call print_string
	jmp .next


.copy_dest_exists:
    ; Load FAT #1
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [copy_dest_drive]
    int 0x13
    jc .copy_failed

    ; Free destination's old chain
    mov ax, [copy_existing_cluster]
    call free_cluster_chain

    ; Save changed FAT to both copies
	; Write FAT #1
	mov bx, 0x0500
    
    mov ah, 0x03
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [copy_dest_drive]
    int 0x13
    jc .copy_failed
	
	; Write FAT #2
    mov bx, 0x0500
    
    mov ah, 0x03
    mov al, 9
    mov ch, 0
    mov cl, 11
    mov dh, 0
    mov dl, [copy_dest_drive]
    int 0x13
    jc .copy_failed

    ; Find space for replacement data
    call find_free_cluster
    jc .copy_disk_full

    ; Reuse the existing directory slot
    call perform_copy
    jc .copy_failed

    mov si, msg_copy_done
    call print_string
    jmp .next

.missing_destination:
    call crlf
	mov si, msg_copy_self
	call print_string
	call crlf

    mov si, msg_zero_copied
	call print_string
	jmp .next

.check_rem:
    cmp byte [si], 'R'
    jne .check_pause
    cmp byte [si+1], 'E'
    jne .check_pause
    cmp byte [si+2], 'M'
    jne .check_pause

    ; REM alone is valid
    cmp byte [si+3], 0
    je .rem_done

    ; Anything following REM must begin with a space
    cmp byte [si+3], ' '
    jne .check_pause

.rem_done:
    call crlf
    jmp .next

.check_pause:
    cmp byte [si], 'P'
    jne .check_rename
    cmp byte [si+1], 'A'
    jne .check_rename
    cmp byte [si+2], 'U'
    jne .check_rename
    cmp byte [si+3], 'S'
    jne .check_rename
    cmp byte [si+4], 'E'
    jne .check_rename
    cmp byte [si+5], 0
    jne .check_rename

    call crlf
    call cmd_pause
    jmp .next

; -----------------------------
; RENAME
; -----------------------------
.check_rename:
    cmp byte [si], 'R'
    jne .check_type
    cmp byte [si+1], 'E'
    jne .check_type
    cmp byte [si+2], 'N'
    jne .check_type
    cmp byte [si+3], 'A'
    jne .check_type
    cmp byte [si+4], 'M'
    jne .check_type
    cmp byte [si+5], 'E'
    jne .check_type

    ; Require space after RENAME
    cmp byte [si+6], ' '
    jne .rename_missing_source

    ; Parse old filename
    add si, 7
    mov di, rename_source
    call parse_filename

    ; Need destination filename
    cmp byte [si], ' '
    jne .rename_missing_dest

.rename_skip_spaces:
    inc si
    cmp byte [si], ' '
    je .rename_skip_spaces

    cmp byte [si], 0
    je .rename_missing_dest

    ; Parse new filename
    mov di, rename_dest
    call parse_filename

    call crlf

    call find_rename_dest
    jnc .rename_error

    call perform_rename
	jc .rename_error

    jmp .next 

.rename_error:
    mov si, msg_rename_error
	call print_string
	jmp .next

.rename_not_found:
    mov si, msg_file_not_found
    call print_string
    jmp .next

.rename_missing_source:
    call crlf
    mov si, msg_missing_file
    call print_string
    jmp .next

.rename_missing_dest:
    call crlf
    mov si, msg_missing_file
    call print_string
    jmp .next

; -----------------------------
; TYPE
; -----------------------------
.check_type:
    cmp byte [si], 'T'
    jne .check_erase
    cmp byte [si+1], 'Y'
    jne .check_erase
    cmp byte [si+2], 'P'
    jne .check_erase
    cmp byte [si+3], 'E'
    jne .check_erase

    ; Require "TYPE filename"
    cmp byte [si+4], ' '
    jne .type_missing

    add si, 5
    mov di, type_filename
    call parse_filename

    call crlf
    call find_type_file
    jc .type_not_found

    call output_type_file
	jc .type_read_error
    jmp .next

.type_read_error:
    mov si, msg_disk_error
	call print_string
	jmp .next

.type_missing:
    call crlf
    mov si, msg_missing_file
    call print_string
    jmp .next

.type_not_found:
    mov si, msg_file_not_found
    call print_string
    jmp .next

; -----------------------------
; ERASE
; -----------------------------
.check_erase:
    cmp byte [si], 'E'
    jne .bad
    cmp byte [si+1], 'R'
    jne .bad
    cmp byte [si+2], 'A'
    jne .bad
    cmp byte [si+3], 'S'
    jne .bad
    cmp byte [si+4], 'E'
    jne .bad

    cmp byte [si+5], ' '
    jne .erase_missing

    add si, 6
    mov di, erase_filename
    call parse_filename

    call crlf
    call find_erase_file
    jc .erase_not_found

    call perform_erase
    jc .erase_error
    jmp .next

.erase_error:
    mov si, msg_disk_error
	call print_string
	jmp .next

.erase_missing:
    call crlf
    mov si, msg_missing_file
    call print_string
    jmp .next

.erase_not_found:
    mov si, msg_file_not_found
    call print_string
    jmp .next

.bad:

	call build_command_tail

	call build_external_name

	call find_external_command
	jnc .external_found

    call crlf
    mov si, msg_bad
    call print_string
	call crlf
	jmp .next

.external_found:

	call load_external_command
    jc .load_failed

	call init_psp

    mov ax, PROGRAM_SEG

    mov ds, ax
    mov es, ax
    mov ss, ax

    mov sp, 0FFFEh

    push cs
    push word .returned

    push PROGRAM_SEG
    push word 0100h

    retf

.returned:

	xor ax, ax
    mov ds, ax
    mov es, ax

    jmp .next

.load_failed:

    call crlf

    mov si, msg_disk_error
    call print_string

    jmp .next

.next:
    call crlf
	jmp main_loop


; -----------------------------
; DIR
; -----------------------------
cmd_dir:
	xor bp, bp
	
	; Root directory starts at LBA 19
    ; LBA 19 = CHS 0/1/2
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .error

    mov di, 0x0500
	mov cx, 16

.next_entry:
    ; 00 = no more entries
    cmp byte [di], 0
    je .done

    ; E5 = deleted entry
    cmp byte [di], 0xE5
    je .skip

    ; Skip VFAT long filename entries
    cmp byte [di+11], 0x0F
    je .skip

    inc bp
	
    push cx
    mov cx, 8

.print_name:
    mov al, [di]
    call print_char
    inc di
    loop .print_name

    mov al, ' '
    call print_char

    mov cx, 3

.print_ext:
    mov al, [di]
    call print_char
    inc di
    loop .print_ext

    ; DI now points at byte 11 of the directory entry.
	; Save DI so we can still advance to the next entry.
	push di

    mov ax, [di+17]
    call print_size

    pop di

	call crlf

    ; We advanced DI by 11 bytes.
    add di, 21

    pop cx
    loop .next_entry
    jmp .done

.skip:
    add di, 32
	loop .next_entry

.done:
    mov ax, bp
	call print_file_count

	mov si, msg_files
	call print_string
	ret

.error:
    call crlf
    call print_not_ready
    call crlf

.drive_error_prompt:
    mov si, msg_abort_retry_ignore
	call print_string

    xor ah, ah
	int 0x16

    mov ah, 0x0E
    int 0x10

    ; Uppercase the answer
	cmp al, 'a'
	jb .check_answer
	cmp al, 'z'
	ja .check_answer
	sub al, 32

.check_answer:
    cmp al, 'R'
	je .retry

    cmp al, 'I'
	je .ignore

    cmp al, 'A'
	je .abort

    ; Invalid response, ask again
	call crlf
	jmp .drive_error_prompt

.retry:
    ; Retry the entire DIR operation
	call crlf
    jmp cmd_dir

.ignore:
    call crlf
    ret

.abort:
    call crlf
    ret


; -----------------------------
; Print file size right-aligned
; in an 8-character field
;
; IN:
;   AX = file size
; -----------------------------
print_size:
    push ax
    push bx
    push cx
    push dx

    ; BX = value whose digits we're counting
    mov bx, ax

    ; At least one digit, even for zero
    mov cx, 1

.count_digits:
    cmp bx, 10
    jb .digits_done

    mov ax, bx
    xor dx, dx
    mov bx, 10
    div bx

    mov bx, ax
    inc cx
    jmp .count_digits

.digits_done:
    ; 8-character field:
    ; spaces = 8 - digits
    mov dx, 9
    sub dx, cx

.print_spaces:
    cmp dx, 0
    je .print_value

    mov al, ' '
    call print_char

    dec dx
    jmp .print_spaces

.print_value:
    pop dx
    pop cx
    pop bx
    pop ax

    call print_number
    ret


; -----------------------------
; Print file count right-aligned
; so "File(s)" starts at column 10
;
; IN:
;   AX = file count
; -----------------------------
print_file_count:
    push ax
    push bx
    push cx
    push dx

    ; Count decimal digits
    mov bx, ax
    mov cx, 1

.count_digits:
    cmp bx, 10
    jb .digits_done

    mov ax, bx
    xor dx, dx
    mov bx, 10
    div bx

    mov bx, ax
    inc cx
    jmp .count_digits

.digits_done:
    ; Count ends at column 9.
    ; Therefore padding = 9 - digit count.
    mov dx, 9
    sub dx, cx

.print_spaces:
    cmp dx, 0
    je .print_count

    mov al, ' '
    call print_char

    dec dx
    jmp .print_spaces

.print_count:
    pop dx
    pop cx
    pop bx
    pop ax

    call print_number
    ret


; -----------------------------
; Print decimal AX
; -----------------------------
print_number:
    xor cx, cx
	mov bx, 10

.divide:
    xor dx, dx
    div bx
    push dx
	inc cx
	
	test ax, ax
	jnz .divide

.print:
    pop ax
	add al, '0'
	mov ah, 0x0E
	int 0x10
	loop .print

	ret


; -----------------------------
; Read full line
; -----------------------------
read_line:
    mov di, input_buffer
    xor cx, cx
	
.read:
    xor ah, ah
	int 0x16
    
    cmp al, 0x0D
    je .done

    cmp al, 0x08
    je .backspace

    ; Echo exactly what was typed
    mov ah, 0x0E
    int 0x10

    ; Convert lowercase to uppercase ONLY in buffer
    mov bl, al

    cmp bl, 'a'
    jb .store
    cmp bl, 'z'
    ja .store

    sub bl, 32

.store:
    mov al, bl
    stosb
    inc cx
    jmp .read

.backspace:
    cmp cx, 0
    je .read

    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10

    dec di
    dec cx
    jmp .read

.done:
    mov al, 0
    stosb
    ret


; -----------------------------
; Print zero-terminated string
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
; New line
; -----------------------------
crlf:
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
	
    mov al, 0x0A
    int 0x10
    ret


; -----------------------------
; Print character
; -----------------------------
print_char:
    mov ah, 0x0E
    int 0x10
    ret


; -----------------------------
; Print prompt
; -----------------------------
print_prompt:
    mov al, [current_drive]
	add al, 'A'
	call print_char
	
	mov al, ':'
	call print_char
	ret


; -----------------------------
; Copy
; -----------------------------
parse_filename:
    push bx
	push dx

    ; Remember beginning of output buffer
	mov bx, di

    ; Fill 11 byte FAT name with spaces
	mov cx, 11

.clear:
    mov byte [di], ' '
    inc di
    loop .clear

    ; Back to beginning
    mov di, bx

    ; Filename length
    xor dx, dx

.name:
    mov al, [si]

    cmp al, 0
    je .done

    cmp al, ' '
    je .done

    cmp al, '.'
    je .extension

    cmp dl, 8
    jae .skip_name

    mov [di], al
    inc di
    inc dl

.skip_name:
    inc si
    jmp .name

.extension:
    inc si

    ; Extension starts at byte 8
    mov di, bx
    add di, 8

    xor dx, dx

.ext_loop:
    mov al, [si]

    cmp al, 0
    je .done

    cmp al, ' '
    je .done

    cmp dl, 3
    jae .skip_ext

    mov [di], al
    inc di
    inc dl

.skip_ext:
    inc si
    jmp .ext_loop

.done:
    pop dx
    pop bx
    ret

SOURCE_FAT equ 0x0500
DEST_FAT   equ 0x0700

; -----------------------------
; Find COPY source file
;
; OUT:
; CF = 0 if found
; CF = 1 if not found
; -----------------------------
find_copy_source:
    ; Read first root-directory sector
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [copy_source_drive]
    int 0x13
    jc .not_found

    mov di, 0x0500
    mov cx, 16

.next_entry:
    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .skip

    push cx
    push di

    mov si, copy_source
    mov cx, 11
    repe cmpsb

    pop di
    pop cx

    je .found

.skip:
    add di, 32
    loop .next_entry

.not_found:
    stc
    ret

.found:
    ; Save starting cluster
    mov ax, [di+26]
    mov [copy_source_cluster], ax

    ; Save 32-bit file size
    mov ax, [di+28]
    mov [copy_source_size], ax

    mov ax, [di+30]
    mov [copy_source_size+2], ax

    clc
    ret

; -----------------------------
; Check whether COPY destination exists
;
; OUT:
;   CF = 0 destination exists
;   CF = 1 destination does not exist
; -----------------------------
find_copy_dest:
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [copy_dest_drive]
    int 0x13
    jc .not_found

    mov di, 0x0500
    mov cx, 16

.next_entry:
    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .skip

	push si
    push cx
    push di

    mov si, copy_dest
    mov cx, 11
    repe cmpsb

    pop di
    pop cx
	pop si

    je .found

.skip:
    add di, 32
    loop .next_entry

.not_found:
    stc
    ret

.found:
    ; Save existing destination's starting cluster
    mov ax, [di+26]
    mov [copy_existing_cluster], ax

    ; Save its root-directory offset
    mov ax, di
    sub ax, 0x0500
    mov [copy_dest_offset], ax

    clc
    ret


; -----------------------------
; Find free root directory entry
;
; OUT:
;   CF = 0 free entry found
;   CF = 1 directory full
; -----------------------------
find_free_dir_entry:
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [copy_dest_drive]
    int 0x13
    jc .full

    mov di, 0x0500
    mov cx, 16

.check:
    ; 00 = unused entry
	cmp byte [di], 0x00
	je .found

	; E5 = deleted/reusable entry
	cmp byte [di], 0xE5
	je .found

	add di, 32
	loop .check

.full:
    stc
	ret

.found:
    ; Save byte offset within root sector,
    ; not a pointer into the temporary buffer
    mov ax, di
    sub ax, 0x0500
    mov [copy_dest_offset], ax

    clc
    ret


; -----------------------------
; Find first free FAT12 cluster
;
; OUT:
;   CF = 0 found
;   CF = 1 disk full
; -----------------------------
find_free_cluster:
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [copy_dest_drive]
    int 0x13
    jc .full

    mov bx, 2

.scan:
    ; FAT12 offset = cluster + cluster/2
	mov ax, bx
	mov dx, bx
	shr ax, 1
	add ax, dx

    mov si, 0x0500
	add si, ax
	mov ax, [si]
	
	; Odd/even entry?
	test bx, 1
	jnz .odd

    and ax, 0x0FFF
	jmp .check

.odd:
    shr ax, 4

.check:
	test ax, ax
	jz .found

	inc bx

	; Good enough boundary for our 1.44 MB floppy
	cmp bx, 0x0FF0
	jb .scan

.full:
    stc
	ret

.found:
    mov [copy_free_cluster], bx
    clc
    ret


; -----------------------------
; Find free FAT12 cluster
; using FAT already in memory
;
; OUT:
; 	CF = 0 found
; 	CF = 1 disk full
; -----------------------------
find_free_cluster_in_memory:

	mov bx, 2

.scan:

	; FAT12 offset = cluster + cluster/2
	mov ax, bx
	mov dx, bx
	shr ax, 1
	add ax, dx

	mov si, DEST_FAT
	add si, ax

	mov ax, [si]

	test bx, 1
	jnz .odd

	and ax, 0x0FFF
	jmp .check

.odd:
	shr ax, 4

.check:
	test ax, ax
	jz .found

	inc bx

	cmp bx, 0x0FF0
	jb .scan

.full:
	stc
	ret

.found:
	mov [copy_free_cluster], bx
	clc
	ret

copy_all_files:

    xor ax, ax
    mov [copy_count], ax

    mov word [wild_offset], 0

.next_file:

    call find_next_wild_file
    jc .done

    call copy_current_file
    jc .next_file

	; Show file being copied
    push si
    push cx

    mov si, copy_dest
    mov cx, 8

.print_name:
    lodsb
    call print_char
    loop .print_name

	mov al, ' '
	call print_char

	mov cx, 3

.print_ext:
	lodsb
    call print_char
    loop .print_ext

    call crlf

    pop cx
    pop si

    inc word [copy_count]
    jmp .next_file

.done:

    mov ax, [copy_count]
    call print_file_count

    mov si, msg_files_copied
    call print_string
    ret

write_copy_directory_entry:
    ; Reload root sector

    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [copy_dest_drive]
    int 0x13
    jc .error

    ; Find saved destination slot
    mov di, 0x0500
    add di, [copy_dest_offset]

    ; Copy 11-byte destination name
    mov si, copy_dest
    mov cx, 11
    rep movsb

    ; Attribute = normal
    mov byte [di], 0

    ; Clear bytes 12-25
    inc di
    mov cx, 14
    xor al, al
    rep stosb

    ; Starting cluster
    mov ax, [copy_first_dest_cluster]
    stosw

    ; File size
    mov ax, [copy_source_size]
    stosw
    mov ax, [copy_source_size+2]
    stosw

    ; -------------------------
    ; Write root directory sector
    ; -------------------------
    mov bx, 0x0500

    mov ah, 0x03
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [copy_dest_drive]
    int 0x13
    jc .error

    clc
    ret

.error:
    stc
    ret

; -----------------------------
; Perform one-cluster COPY
; -----------------------------
perform_copy:
    ; -------------------------
    ; Read source cluster
    ; into 0000:2000
    ; -------------------------
    mov ax, [copy_source_cluster]
    call cluster_to_chs

    xor ax, ax
    mov es, ax
    mov bx, 0x2000

    mov ah, 0x02
    mov al, 1
    mov dl, [copy_source_drive]
    int 0x13
    jc .error

    ; -------------------------
    ; Write data to new cluster
    ; -------------------------
    mov ax, [copy_free_cluster]
    call cluster_to_chs

    mov bx, 0x2000

    mov ah, 0x03
    mov al, 1
    mov dl, [copy_dest_drive]
    int 0x13
    jc .error

    ; -------------------------
    ; Load FAT #1 to 0500h
    ; -------------------------
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [copy_dest_drive]
    int 0x13
    jc .error

    ; Mark destination cluster FFF
    mov bx, [copy_free_cluster]

    mov ax, bx
    mov dx, bx
    shr ax, 1
    add ax, dx

    mov si, 0x0500
    add si, ax

    test bx, 1
    jnz .fat_odd

    ; even FAT12 entry
    mov ax, [si]
    and ax, 0xF000
    or ax, 0x0FFF
    mov [si], ax
    jmp .fat_ready

.fat_odd:
    mov ax, [si]
    and ax, 0x000F
    or ax, 0xFFF0
    mov [si], ax

.fat_ready:
    ; Write FAT #1
    mov bx, 0x0500

    mov ah, 0x03
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [copy_dest_drive]
    int 0x13
    jc .error

    ; Write identical FAT #2
    mov bx, 0x0500

    mov ah, 0x03
    mov al, 9
    mov ch, 0
    mov cl, 11
    mov dh, 0
    mov dl, [copy_dest_drive]
    int 0x13
    jc .error

    call write_copy_directory_entry
	jc .error

    clc
	ret

.error:
    stc
    ret

perform_multicluster_copy:

	; Load source FAT
	xor ax, ax
	mov es, ax
	mov bx, SOURCE_FAT

	mov ah, 0x02
	mov al, 9
	mov ch, 0
	mov cl, 2
	mov dh, 0
	mov dl, [copy_source_drive]
	int 0x13
	jc .error

    ; -------------------------
	; Load destination FAT
	; -------------------------
	mov bx, DEST_FAT

	mov ah, 0x02
	mov al, 9
	mov ch, 0
	mov cl, 2
	mov dh, 0
	mov dl, [copy_dest_drive]
	int 0x13
	jc .error

	; Beginning of source chain
	mov ax, [copy_source_cluster]
	mov [copy_current_source_cluster], ax

	xor ax, ax
	mov [copy_first_dest_cluster], ax
	mov [copy_previous_dest_cluster], ax

.copy_loop:

	; Read source cluster
	mov ax, [copy_current_source_cluster]
	call cluster_to_chs

	xor ax, ax
	mov es, ax
	mov bx, 0x2000

	mov ah, 0x02
	mov al, 1
	mov dl, [copy_source_drive]
	int 0x13
	jc .error

	; Find a destination cluster
	call find_free_cluster_in_memory
	jc .error

	mov ax, [copy_free_cluster]
	mov [copy_current_dest_cluster], ax

	; Reserve cluster immediately so allocator
	; will not find it again next iteration.

	mov bx, [copy_current_dest_cluster]

	mov ax, bx
	mov dx, bx
	shr ax, 1
	add ax, dx

	mov si, DEST_FAT
	add si, ax

	test bx, 1
	jnz .reserve_odd

	; Even FAT12 entry
	mov ax, [si]
	and ax, 0xF000
	or ax, 0x0FFF
	mov [si], ax
	jmp .reserved

.reserve_odd:
	mov ax, [si]
	and ax, 0x000F
	or ax, 0xFFF0
	mov [si], ax

.reserved:

	; Link previous destination cluster
	cmp word [copy_previous_dest_cluster], 0
	je .no_previous

	mov bx, [copy_previous_dest_cluster]

	; FAT12 offset = cluster + cluster/2
	mov ax, bx
	mov dx, bx
	shr ax, 1
	add ax, dx

	mov si, DEST_FAT
	add si, ax

	test bx, 1
	jnz .link_odd

	; Even entry
	mov ax, [si]
	and ax, 0xF000
	or ax, [copy_current_dest_cluster]
	mov [si], ax
	jmp .no_previous

.link_odd:
	mov ax, [si]
	and ax, 0x000F

	mov dx, [copy_current_dest_cluster]
	shl dx, 4

	or ax, dx
	mov [si], ax

.no_previous:

    ; -------------------------
	; Remember first cluster
	; -------------------------
	cmp word [copy_first_dest_cluster], 0
	jne .not_first

	mov ax, [copy_current_dest_cluster]
	mov [copy_first_dest_cluster], ax

.not_first:

    mov ax, [copy_current_dest_cluster]
	mov [copy_previous_dest_cluster], ax

    ; Write destination cluster
    mov ax, [copy_current_dest_cluster]
	call cluster_to_chs

	mov bx, 0x2000

	mov ah, 0x03
	mov al, 1
	mov dl, [copy_dest_drive]
	int 0x13
	jc .error

    ; -------------------------
	; Advance source chain
	; -------------------------
	mov ax, [copy_current_source_cluster]
    call get_next_cluster

	cmp ax, 2
	jb .finish

	cmp ax, 0x0FF8
	jae .finish

.finish:

    mov bx, [copy_previous_dest_cluster]

	mov ax, bx
	mov dx, bx
	shr ax, 1
	add ax, dx

	mov si, DEST_FAT
	add si, ax

	test bx, 1
	jnz .final_odd

	mov ax, [si]
	and ax, 0xF000
	or ax, 0x0FFF
	mov [si], ax
	jmp .fat_ready

.final_odd:
	mov ax, [si]
	and ax, 0x000F
	or ax, 0xFFF0
	mov [si], ax

.fat_ready:
    ; FAT #1
	mov bx, DEST_FAT

	mov ah, 0x03
	mov al, 9
	mov ch, 0
	mov cl, 2
	mov dh, 0
	mov dl, [copy_dest_drive]
	int 0x13
	jc .error

	; FAT #2
	mov bx, DEST_FAT

	mov ah, 0x03
	mov al, 9
	mov ch, 0
	mov cl, 11
	mov dh, 0
	mov dl, [copy_dest_drive]
	int 0x13
	jc .error

    call write_copy_directory_entry
	jc .error

	clc
	ret

.error:
    stc
    ret

cluster_to_chs:
    ; AX = cluster
    ; cluster 2 = LBA 33

    sub ax, 2
    add ax, 33

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
    ret


cmd_pause:
    mov si, msg_pause
    call print_string

    xor ah, ah
    int 0x16

    ret


; -----------------------------
; Perform Multicopy
; -----------------------------
copy_current_file:

    call find_copy_dest
    jnc .exists

    call find_free_dir_entry
    jc .fail

    call find_free_cluster
    jc .fail

    call perform_multicluster_copy
    jc .fail

    clc
    ret

.exists:
.fail:
    stc
    ret


; -----------------------------
; Perform Multicopy continued
; -----------------------------
find_next_wild_file:

    xor ax, ax
    mov es, ax
    mov bx, 0x0900

    ; Read source root directory
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [copy_source_drive]
    int 0x13
    jc .not_found

    mov di, 0x0900
    add di, [wild_offset]

.scan:

    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .next

    cmp byte [di+11], 0x0F
    je .next

	; Copy actual filename into copy_source
    push di

    mov si, di
    mov di, copy_source

    mov cx, 11
    rep movsb

    pop di

    ; Copy actual filename into copy_dest
    push di

    mov si, copy_source
    mov di, copy_dest

    mov cx, 11
    rep movsb

    pop di

    ; Save source cluster
    mov ax, [di+26]
    mov [copy_source_cluster], ax

    ; Save source file size
    mov ax, [di+28]
    mov [copy_source_size], ax

    mov ax, [di+30]
    mov [copy_source_size+2], ax

    ; Advance wildcard scan
    add word [wild_offset], 32

    clc
    ret

.next:
	
	add di, 32
    add word [wild_offset], 32
    jmp .scan

.not_found:
    stc
    ret


; -----------------------------
; Perform RENAME
; -----------------------------
perform_rename:
    ; Load first root directory sector
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .error

    mov di, 0x0500
    mov dx, 16

.search:
    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .next

    push di
    mov si, rename_source
    mov cx, 11
    repe cmpsb
    pop di

    je .found

.next:
    add di, 32
    dec dx
    jnz .search

.not_found:
.error:
    stc
    ret

.found:
    ; Replace ONLY the 11-byte filename
    push di

    mov si, rename_dest
    mov cx, 11
    rep movsb

    pop di

    ; Write root-directory sector back
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x03
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .error

    clc
    ret


; -----------------------------
; Check if RENAME destination exists
;
; OUT:
; CF = 0 = already exists
; CF = 1 = does not exist
; -----------------------------
find_rename_dest:
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    ; Root directory sector
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .not_found

    mov di, 0x0500
    mov dx, 16

.next_entry:
    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .skip

    push di
    mov si, rename_dest
    mov cx, 11
    repe cmpsb
    pop di

    je .found

.skip:
    add di, 32
    dec dx
    jnz .next_entry

.not_found:
    stc
    ret

.found:
    clc
    ret


; -----------------------------
; Find TYPE file
; -----------------------------
find_type_file:
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    ; First root directory sector
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .not_found

    mov di, 0x0500
    mov dx, 16

.search:
    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .next

    push di
    mov si, type_filename
    mov cx, 11
    repe cmpsb
    pop di

    je .found

.next:
    add di, 32
    dec dx
    jnz .search

.not_found:
    stc
    ret

.found:
    mov ax, [di+26]
    mov [type_cluster], ax

    mov ax, [di+28]
    mov [type_size], ax

    mov ax, [di+30]
    mov [type_size+2], ax

    clc
    ret


; -----------------------------
; Output TYPE file
; -----------------------------
output_type_file:

	; Load FAT #1
	xor ax, ax
	mov es, ax
	mov bx, SOURCE_FAT

	mov ah, 0x02
	mov al, 9
	mov ch, 0
	mov cl, 2
	mov dh, 0
	mov dl, [current_drive]
	int 0x13
	jc .error

	; Start at first cluster
	mov ax, [type_cluster]
	mov [type_current_cluster], ax

.loop:

	; Read current cluster
	mov ax, [type_current_cluster]
	call cluster_to_chs

	xor ax, ax
	mov es, ax
	mov bx, 0x1000

	mov ah, 0x02
	mov al, 1
	mov dl, [current_drive]
	int 0x13
	jc .error

	; Determine how many bytes to print
	mov cx, [type_size]

	cmp cx, 512
	jbe .have_count

	mov cx, 512

.have_count:

	mov si, 0x1000

.print:
	cmp cx, 0
	je .cluster_done

	lodsb

	mov ah, 0x0E
	int 0x10

	dec cx
	jmp .print

.cluster_done:

	; Reduce remaining size
	cmp word [type_size], 512
	jb .last_cluster

	sub word [type_size], 512
	jmp .next_cluster

.last_cluster:
    xor ax, ax
	mov [type_size], ax

.next_cluster:

	cmp word [type_size], 0
	je .done

	mov ax, [type_current_cluster]
	call get_next_cluster

	cmp ax, 2
	jb .done

	cmp ax, 0x0FF8
	jae .done

	mov [type_current_cluster], ax
	jmp .loop

.done:
    clc
    ret


.error:
    stc
    ret


find_erase_file:
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    ; Read first root-directory sector
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .not_found

    mov di, 0x0500
    mov dx, 16

.search:
    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .next

    push di
    mov si, erase_filename
    mov cx, 11
    repe cmpsb
    pop di

    je .found

.next:
    add di, 32
    dec dx
    jnz .search

.not_found:
    stc
    ret

.found:
    mov ax, [di+26]
    mov [erase_cluster], ax

    ; Save entry offset within root sector
    mov ax, di
    sub ax, 0x0500
    mov [erase_entry_offset], ax

    clc
    ret


; -----------------------------
; Perform ERASE
; -----------------------------
perform_erase:
    ; Load FAT #1 at 0500h
    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [current_drive]
    int 0x13
    jc .error

    mov ax, [erase_cluster]
	call free_cluster_chain
	
.fat_done:
    ; -----------------------------
    ; Write FAT #1
    ; -----------------------------
    mov bx, 0x0500

    mov ah, 0x03
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [current_drive]
    int 0x13
    jc .error

    ; -----------------------------
    ; Write FAT #2
    ; -----------------------------
    mov bx, 0x0500

    mov ah, 0x03
    mov al, 9
    mov ch, 0
    mov cl, 11
    mov dh, 0
    mov dl, [current_drive]
    int 0x13
    jc .error

    ; -----------------------------
    ; Reload root directory sector
    ; -----------------------------
    mov bx, 0x0500

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .error

    ; -----------------------------
    ; Mark directory entry deleted
    ; -----------------------------
    mov di, 0x0500
    add di, [erase_entry_offset]

    mov byte [di], 0xE5

    ; -----------------------------
    ; Write root directory back
    ; -----------------------------
    mov bx, 0x0500

    mov ah, 0x03
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .error

    clc
    ret

.error:
    stc
    ret


; -----------------------------
; Free FAT12 cluster chain
;
; IN:
;   AX = first cluster to free
;
; FAT #1 must already be loaded
; at 0000:0500
; -----------------------------
free_cluster_chain:
    mov bx, ax

.free:
    ; FAT12 byte offset:
    ; cluster + cluster / 2
    mov ax, bx
    mov dx, bx
    shr ax, 1
    add ax, dx

    mov si, 0x0500
    add si, ax

    ; Read old next-cluster value
    mov ax, [si]

    test bx, 1
    jnz .odd

    ; Even cluster
    and ax, 0x0FFF
    mov dx, ax

    ; Mark current cluster free
    mov ax, [si]
    and ax, 0xF000
    mov [si], ax
    jmp .next

.odd:
    ; Odd entry
    shr ax, 4
    mov dx, ax

    ; Mark current cluster free
    mov ax, [si]
    and ax, 0x000F
    mov [si], ax

.next:
    ; End of FAT chain?
    cmp dx, 0x0FF8
    jae .done

    ; Bougus/free/reserved low value?
    cmp dx, 2
	jb .done

	mov bx, dx
	jmp .free

.done:
    ret

; -----------------------------
; Get next FAT12 cluster
;
; IN:
;   AX = current cluster
;
; OUT:
;   AX = next cluster
;
; FAT #1 must already be loaded
; at 0000:0500
; -----------------------------
get_next_cluster:

	mov bx, ax

	; FAT12 offset:
	; cluster + cluster/2
	mov ax, bx
	mov dx, bx
	shr ax, 1
	add ax, dx

	mov si, SOURCE_FAT
	add si, ax

	mov ax, [si]

	test bx, 1
	jnz .odd

	; Even entry
	and ax, 0FFFh
	ret

.odd:
	shr ax, 4
	and ax, 0FFFh
	ret

print_not_ready:
    mov si, msg_not_ready
    call print_string

    mov al, [current_drive]
    add al, 'A' 
    call print_char

    ret

; -----------------------------
; Load external file
; -----------------------------
find_external_command:

    xor ax, ax
    mov es, ax
    mov bx, 0x0500

    ; Read root directory
    mov ah, 0x02
    mov al, 14
    mov ch, 0
    mov cl, 2
    mov dh, 1
    mov dl, [current_drive]
    int 0x13
    jc .not_found

    mov di, 0x0500
    mov cx, 224

.next_entry:

    cmp byte [di], 0
    je .not_found

    cmp byte [di], 0xE5
    je .skip

    push cx
    push di

    mov si, external_filename
    mov cx, 11
    repe cmpsb

    pop di
    pop cx

    je .found

.skip:
    add di, 32
    loop .next_entry

.not_found:
    stc
    ret

.found:
    mov ax, [di+26]
    mov [external_cluster], ax

	push ax
	call print_number
	call crlf
	pop ax

    mov ax, [di+28]
    mov [external_size], ax

    mov ax, [di+30]
    mov [external_size+2], ax

    clc
    ret


build_external_name:

    push di
    push cx

    mov di, external_filename

    ; Fill with spaces
    mov cx, 11
.fill:
    mov byte [di], ' '
    inc di
    loop .fill

    mov di, external_filename
    mov si, input_buffer

    mov cx, 8

.copy_name:
    mov al, [si]

    cmp al, 0
    je .add_com

    cmp al, ' '
    je .add_com

    mov [di], al

    inc si
    inc di
    loop .copy_name

.add_com:
    mov byte [external_filename+8], 'C'
    mov byte [external_filename+9], 'O'
    mov byte [external_filename+10], 'M'

    pop cx
    pop di
    ret


load_external_command:

    ; Load source FAT
    xor ax, ax
    mov es, ax
    mov bx, SOURCE_FAT

    mov ah, 0x02
    mov al, 9
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [current_drive]
    int 0x13
    jc .error

	mov ax,[0500h]
	call print_number
	call crlf

	mov ax,[0502h]
	call print_number
	call crlf

	mov ax,[0504h]
	call print_number
	call crlf

    ; Start cluster
    mov ax, [external_cluster]
    mov [external_current_cluster], ax

	mov word [external_load_offset], COM_LOAD

.next_cluster:

    mov ax, [external_current_cluster]
    call cluster_to_chs

    mov ax, PROGRAM_SEG
    mov es, ax

	mov bx, [external_load_offset]

    mov ah, 0x02
    mov al, 1
    mov dl, [current_drive]
    int 0x13
    jc .error

    add word [external_load_offset], 512

    mov ax, [external_current_cluster]
	call print_number
	call crlf

    call get_next_cluster

	push ax
	call print_number
	call crlf
	pop ax

    cmp ax, 2
    jb .done

    cmp ax, 0x0FF8
    jae .done

    mov [external_current_cluster], ax

    jmp .next_cluster

.done:

    clc
    ret

.error:

    stc
    ret


init_psp:

    mov ax, PROGRAM_SEG
    mov es, ax

    xor di, di
    xor ax, ax

    mov cx, 128
    rep stosw

    ; PSP:0000 = INT 20h
    mov byte [es:0], 0CDh
    mov byte [es:1], 20h

    ; Empty command tail
    mov al,[command_tail_length]
	mov [es:80h],al

	mov si,command_tail
	mov di,81h

	xor ch,ch
	mov cl,[command_tail_length]

	rep movsb

	mov byte [es:di],13

    ret


build_command_tail:

    mov byte [command_tail_length],0

    mov si,input_buffer

.find_space:
    mov al,[si]

    cmp al,0
    je .done

    cmp al,' '
    je .found

    inc si
    jmp .find_space

.found:

.skip_spaces:
    inc si

    cmp byte [si],' '
    je .skip_spaces

    cmp byte [si],0
    je .done

    mov di,command_tail
    xor cx,cx

.copy:

    mov al,[si]

    cmp al,0
    je .finish

    mov [di],al

    inc di
    inc si
    inc cx

    jmp .copy

.finish:

    mov [command_tail_length],cl

.done:
    ret


; -----------------------------
; Data
; -----------------------------
banner:
    db 'Command v. 1.17',0

current_drive:
    db 0 ; A:

drive_count:
    db 1 ; default: only A:

msg_bad:
    db 'Bad command or file name',0
	
msg_disk_error:
    db 'Disk read error',0

msg_files:
    db ' File(s)',0

msg_invalid_drive:
    db 'Invalid drive specification',0

msg_missing_file:
    db 'Missing file name',0

msg_missing_destination:
    db 'Missing destination file',0

msg_copy_test:
    db 'COPY arguments detected',0

msg_copy_parsed:
    db 'COPY arguments detected',0

msg_copy_self:
    db 'File cannot be copied onto itself',0

msg_zero_copied:
    times 8 db ' ' 
	db '0 File(s) copied',0

copy_source_cluster:
    dw 0

copy_source_size:
    dd 0

msg_source_found:
    db 'Source file found',0

msg_file_not_found:
    db 'File not found',0

msg_file_exists:
    db 'File already exists',0

msg_copy_ready:
    db 'Ready to copy',0

copy_dest_offset:
    dw 0

msg_directory_full:
    db 'Directory full',0

copy_free_cluster:
    dw 0

msg_disk_full:
    db 'Insufficient disk space',0

msg_copy_done:
    db '        1 File(s) copied',0

msg_files_copied:
    db ' File(s) copied',0
	
msg_copy_too_large:
    db 'File too large for COPY',0

msg_pause:
    db 'Strike a key when ready . . . ',0

rename_source:
    times 11 db 0

rename_dest:
    times 11 db 0

msg_rename_parsed:
    db 'RENAME arguments detected',0

msg_rename_error:
    db 'Duplicate file name or File not found',0

type_filename:
    times 11 db 0

type_cluster:
    dw 0

type_current_cluster:
    dw 0

type_size:
    dd 0

msg_type_too_large:
    db 'File too large',0

msg_type_found:
    db 'TYPE file found',0

erase_filename:
    times 11 db 0

erase_cluster:
    dw 0

erase_entry_offset:
    dw 0

msg_erase_found:
    db 'ERASE file found',0

msg_not_ready:
    db 'Not ready reading drive ',0

msg_abort_retry_ignore:
    db 'Abort, Retry, Ignore? ',0

copy_source_drive:
    db 0

copy_dest_drive:
    db 0

copy_source:
    times 11 db 0

copy_dest:
    times 11 db 0

copy_existing_cluster:
    dw 0

copy_first_dest_cluster:
	dw 0

copy_previous_dest_cluster:
	dw 0

copy_current_source_cluster:
	dw 0

copy_current_dest_cluster:
	dw 0

copy_count:
	dw 0

msg_exists:
    db 'DEST EXISTS',0

msg_source_ok:
    db 'SOURCE OK',0

msg_source_fail:
    db 'SOURCE FAIL',0

msg_dest_ok:
    db 'DEST OK',0

msg_dir_ok:
    db 'DIR OK',0

msg_cluster_ok:
    db 'CLUSTER OK',0

copy_entries_left:
	dw 0

wild_offset:
	dw 0

external_filename:
    times 11 db 0

external_cluster:
    dw 0

external_size:
    dd 0

msg_external_found:
    db 'External command located',0

COM_LOAD equ 0x0100

external_current_cluster:
    dw 0

external_load_offset:
    dw COM_LOAD
 
PROGRAM_SEG equ 0x2000

command_tail_length:
	db 0

command_tail:
	times 128 db 0

input_buffer:
    times 128 db 0