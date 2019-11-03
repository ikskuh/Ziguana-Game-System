bits 32

init:
	mov eax, 0x11223344
	mov eax, [0x11223344]
	mov eax, [eax]
	mov eax, [eax+0x11223344]
	mov ebx, [0x11223344]
	
	nop

	mov [0x11223344], eax
	mov [ebx], eax
	mov [ebx+0x11223344], eax
	
	nop

	jmp eax
	jmp [eax]
	jmp [0x11223344]
	jmp [eax+0x11223344]
	jmp dword 0x11223344
