org 100h

start:

	mov ax,cs
    mov ds,ax
    mov es,ax

	; Parse required drive parameter

	mov cl,[80h]
    xor ch,ch

    cmp cx,0
    je missing_parameter

	mov si,81h

.skip_spaces:
    cmp byte [si],' '
    jne .check_param

    inc si
    jmp .skip_spaces  

.check_param:

    mov al,[si]

    cmp byte [si+1],':'
    jne missing_parameter

    cmp al,'A'
    jb invalid_parameter

    cmp al,'Z'
    ja invalid_parameter

	mov bl,al

    sub al,'A'
    mov [format_drive],al

    ; Verify drive exists
    mov dl,al

    xor ah,ah
    int 13h
    jc invalid_parameter

    mov [format_drive_letter],bl

	call crlf
	call crlf

	mov si,msg_insert1
    call print_string

    mov al,[format_drive_letter]
    mov ah,0Eh
    int 10h
	
	mov si,msg_insert2
	call print_string

	xor ah,ah
	int 16h

format_disk:

	call crlf
	call crlf
	call crlf

	mov si,msg_formatting
	call print_string
	call crlf

	call fmt_init
    jc format_error

    call fmt_diskformat
    jc format_error

    call fmt_wrtfat
    jc format_error

    call fmt_done
    jc format_error

	mov si,msg_total
	call print_string

	call crlf

	mov si,msg_free
	call print_string

	call crlf
	call crlf

ask_again:

.ask:

	mov si,msg_again
	call print_string

.wait:

	xor ah,ah
	int 16h

	cmp al,13
    je .reprompt

	; Ignore Backspace when no answer exists
    cmp al,8
    je .wait

	; Echo whatever was typed
	mov ah,0Eh
	int 10h

	cmp al,'Y'
	je .got_yes

	cmp al,'y'
	je .got_yes

	cmp al,'N'
	je .got_no

	cmp al,'n'
	je .got_no

    ; Invalid key
    mov byte [answer],'?'
    jmp .invalid_wait

.got_yes:

	mov byte [answer],'Y'
    jmp .wait_enter

.got_no:

	mov byte [answer],'N'
    jmp .wait_enter

.wait_enter:

    xor ah,ah
    int 16h

    cmp al,13
    je .execute

	cmp al,8
    je .erase_answer

    jmp .wait_enter

.invalid_wait:

    xor ah,ah
    int 16h

    cmp al,13
    je .reprompt

    cmp al,8
    je .erase_answer

    jmp .invalid_wait

.execute:

    call crlf

    cmp byte [answer],'Y'
    je format_disk

	cmp byte [answer],'N'
    je .quit

	; Invalid answer
    jmp .ask
	
.quit:

    retf

.reprompt:

    call crlf
    jmp .ask

.erase_answer:

    ; erase echoed character
    mov ah,0Eh

    mov al,8
    int 10h

    mov al,' '
    int 10h

    mov al,8
    int 10h

    mov byte [answer],0

    jmp .wait

missing_parameter:

	call crlf

    mov si,msg_missing_parameter
    call print_string

    call crlf
    retf


invalid_parameter:

	call crlf

    mov si,msg_invalid_parameter
    call print_string

    call crlf
    retf


format_error:

	call crlf

	mov si,msg_error
	call print_string

	call crlf

	retf


fmt_init:
    clc
    ret

fmt_diskformat:
    clc
    ret

fmt_wrtfat:
    clc
    ret

fmt_done:
    clc
    ret

print_string:

.next:
    lodsb
    test al,al
    jz .done

    mov ah,0Eh
    int 10h
    jmp .next

.done:
    ret


crlf:

	mov ah,0Eh

	mov al,13
	int 10h

	mov al,10
	int 10h

	ret


format_drive:
    db 0

format_drive_letter:
    db 'A'

msg_insert1:
	db 'Insert new diskette for drive ',0

msg_insert2:
    db ':',13,10
    db 'and strike any key when ready',0

msg_formatting:
	db 'Formatting ...',0

msg_total:
	db '  1457664 bytes total disk sp',0

msg_free:
	db 'FREE',0

msg_again:
	db 'Format another (Y/N)?',0

msg_missing_parameter:
	db 'Required parameter missing -',0

msg_invalid_parameter:
	db 'Invalid drive specification',0

msg_error:
	db 'Format failure',0

answer:
	db 0
