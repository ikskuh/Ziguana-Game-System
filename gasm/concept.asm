resetGame:


clearScreen:
	mov r1, 0 # Y
.loopY:
	mov r0, 0 # X
.loopX:
	setpix r0, r1, [color]
	add r0, 1
	cmp r0, 320
	jnz .loopX
	
	add r1, 1
	cmp r1, 200
	jnz .loopY # jump non-zero

	# Refresh screen
	flushpix


waitsome:
	gettime [time]
	add [time], 100
.loop:
	gettime r0
	cmp [time], r0
	jgz .loop
	
	add [color], 1

	jmp clearScreen


time:
	.dw 0

color:
	.dw 0
