# Implements a simple "light race game"
# Control player with arrow keys
# Don't hit your own trace


# Workspace:
#	jsr label
#	push x
#	pop x
#	and, or, inv, neg
#

.def BGCOLOR, 0
.def PLAYERCOLOR, 1
.def RED, 4
.def UP,    0x10048 # escaped0 scancode 72 ↑
.def LEFT,  0x1004B # escaped0 scancode 75 ←
.def DOWN,  0x10050 # escaped0 scancode 80 ↓
.def RIGHT, 0x1004D # escaped0 scancode 77 →
.def SPACE, 0x00039 # space
init:
	jmp resetGame

resetGame:
	mov [playerX], 320
	mov [playerY], 240
	mov [playerDir], 4 # stop

	# clear screen
	trace 3 # buffered Pixel API
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

	# Refresh screen
	flushpix

	trace 2 # immediate Pixel API

gameLoop:
	# Store the time stamp for the next frame
	gettime [nextFrame]
	add [nextFrame], 16

	setpix [playerX], [playerY], 1

	# Load dx, dy into r1, r2
	mov r0, [playerDir]
	mul r0, 8
	add r0, dirs
	mov r1, [r0+0]
	mov r2, [r0+4]

	# Move player a bit
	add [playerX], r1
	add [playerY], r2

	# Test if we hit something
	# but only if we are moving
	cmp [playerDir], 4
	jiz .skipHitTest
	getpix r0, [playerX], [playerY]
	cmp r0, BGCOLOR
	jnz loseGame
.skipHitTest:

	# Now test for movement
	getkey r0 # returns last pressed key scancode and resets it to 0
	cmp r0, UP
	jiz .moveUp
	cmp r0, DOWN
	jiz .moveDown
	cmp r0, LEFT
	jiz .moveLeft
	cmp r0, RIGHT
	jiz .moveRight

	trace 1
.vsync:
	gettime r0
	cmp r0, [nextFrame]
	jlz .vsync # jump less than zero 

	trace 0
	jmp gameLoop
	
.moveUp:
	mov [playerDir], 1
	jmp .vsync

.moveDown:
	mov [playerDir], 3
	jmp .vsync

.moveRight:
	mov [playerDir], 0
	jmp .vsync

.moveLeft:
	mov [playerDir], 2
	jmp .vsync

loseGame:
	# sad...

	trace 3 # buffered Pixel API

	# clear screen
	mov r1, 0 # Y
.loopY: # local labels are only valid between two global labels
	mov r0, 0 # X
.loopX:
	setpix r0, r1, RED
	add r0, 1
	cmp r0, 640
	jnz .loopX

	# this takes sufficient time
	mov r2, r1
	and r2, 0x0F
	cmp r2, 0
	jnz .skipFlush

	flushpix
.skipFlush:
	
	add r1, 1
	cmp r1, 480
	jnz .loopY # jump non-zero

	flushpix

.loop:
	getkey r0
	cmp r0, SPACE
	jiz resetGame

	jmp .loop

.align 4

playerX:
	.dw 320
playerY:
	.dw 240
playerDir:
	.dw 0

dirs:
	.dw 1, 0
	.dw 0, 0xFFFFFFFF
	.dw 0xFFFFFFFF, 0
	.dw 0, 1
	.dw 0, 0

nextFrame:
	.dw 0


