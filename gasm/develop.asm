.def BGCOLOR, 0
.def PLAYERCOLOR, 1
.def UP,    0x10048 # escaped0 scancode 72
.def LEFT,  0x1004B # escaped0 scancode 75
.def DOWN,  0x10050 # escaped0 scancode 80
.def RIGHT, 0x1004D # escaped0 scancode 77

init: jmp resetGame

resetGame:
	mov [playerX], 320
	mov [playerY], 240
	mov [playerDir], 0

	# clear screen
	mov r1, 0 # Y
.loopY: # local labels are only valid between two global labels
	mov r0, 0 # X
.loopX:
	setpix r0, r1, BGCOLOR
	add r0, 1
	cmp r0, 640
	jnz .loopX
	
	add r1, 1
	cmp r1, 480
	jnz .loopY # jump non-zero

gameLoop:
	# Store the time stamp for the next frame
	gettime [nextFrame]
	add [nextFrame], 16

	setpix [playerX], [playerY], 1

	# Load dx, dy into r1, r2
	mov r0, [playerDir]
	shl r0, 1
	add r0, dirs
	mov r1, [r0+0]
	mov r2, [r0+4]

	# Move player a bit
	add [playerX], r1
	add [playerY], r2

	# Test if we hit something
	getpix r0, [playerX], [playerY]
	cmp r0, BGCOLOR
	jnz loseGame

	# Now test for movement
	getkey r0 # returns last pressed key scancode and resets it to 0
	cmp r0, UP
	jnz .moveUp
	cmp r0, DOWN
	jnz .moveDown
	cmp r0, LEFT
	jnz .moveLeft
	cmp r0, RIGHT
	jnz .moveRight

.vsync:
	gettime r0
	cmp r0, nextFrame
	jlz .vsync # jump less than zero 

	jmp gameLoop
	
.moveUp:
	mov [dir], 1
	jmp .vsync

.moveDown:
	mov [dir], 3
	jmp .vsync

.moveRight:
	mov [dir], 0
	jmp .vsync

.moveLeft:
	mov [dir], 2
	jmp .vsync

loseGame:
	# sad...
	jmp loseGame

.align 4

playerX:
	.dw 320
playerY:
	.dw 240
playerDir:
	.dw 0

dirs:
	.dw 1, 0
	.dw 0, 1
	.dw 0xFFFFFFFF, 0
	.dw 0, 0xFFFFFFFF

nextFrame:
	.dw 0
