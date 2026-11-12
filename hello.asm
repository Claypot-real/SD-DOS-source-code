org 100h

mov si,msg

.print:
    lodsb
    test al,al
    jz .done

    mov ah,0Eh
    int 10h

    jmp .print

.done:
    retf

msg db 'Hello from HELLO.COM',0