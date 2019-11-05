bits 32

init:
	mov eax, 0x11223344
	mov eax, [0x11223344]
	mov eax, [eax]
	mov eax, [eax+0x11223344]
	mov ebx, [0x11223344]
	
	nop
	
	mov ebx, eax
	mov eax, ebx
	add eax, ebx
	sub eax, ebx
	cmp eax, ebx

	nop

	mov [0x11223344], eax
	mov [ebx], eax
	mov [ebx+0x11223344], eax
	
	nop

	jmp eax
	jmp [eax]
	jmp [0x11223344]
	jmp [eax+0x11223344]

	nop

	jz next
	jnz next
	jge next
	jle next
	jmp eax
	jmp eax

	nop

	push eax
	mov eax, 0x11223344
	call eax
	pop eax

	nop

	push 0x11223344
	push eax
    call next
    add esp,0x55
	
	nop
	
	mul ebx
	div ebx
	mov eax, edx

	nop

	int 0x30

next:
	nop
