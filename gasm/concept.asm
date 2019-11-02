# Implements a simple "light race game"
# Control player with arrow keys
# Don't hit your own trace

# Registers (32 bit):
# 	r0...r15
#
# Flags:
# 	C: Carry
#	Z: Zero
#
# Operand Format:
#	r0 … r15 are register names and reserved
#	decimal or hexadecimal numbers are used as literals
#	label names can be used instead of literals for the address of the label
#	[…] is an indirection and stores/loads from the memory address … instead of using … as an immediate value
#
# Note: *x means that x may be modified
# Instructions:
#	mov *dst, src    | copies src to dst
#	add *dst, val    | adds val to dst
#	cmp a, b         | compares a to b and stores result in flags. Z is set when a==b, C is set when a < b
#	jmp dst          | jumps execution to address dst
#	jnz	dst          | jumps execution to address dst when Z is set
#	jlz dst          | jumps execution to address dst when C is set
#   jgz dst          | jumps execution to address dst when both Z  and C are not set
#   jiz dst          | jumps execution to address dst when Z is not set
#	shl *dst, cnt    | shifts dst cnt bits to the left
#	shr *dst, cnt    | shifts dst cnt bits to the right
#	gettime *dst     | stores the current system time in ms into dst
#	setpix x,y,c     | sets pixel (x,y) to color c
#	getpix *c,x,y    | gets pixel (x,y) into c
#
# Directives:
#	.def NAME, value | creates new constant NAME with value value.
#	.dw a,…          | stores literal 32bit word a, … at the current position
#
# Labels:
#	name:            | global label "name"
#	.loc:            | local label "loc". can only be used/references between to global labels.

.def BGCOLOR, 0
.def PLAYERCOLOR, 1
.def UP,    0x10048 # escaped0 scancode 72
.def LEFT,  0x1004B # escaped0 scancode 75
.def DOWN,  0x10050 # escaped0 scancode 80
.def RIGHT, 0x1004D # escaped0 scancode 77

init:
	jmp resetGame

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
	mov r2, [r0+1]

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

playerX:
	.dw 320
playerY:
	.dw 240
playerDir:
	.dw 0

dirs:
	.dw 1, 0
	.dw 0, 1
	.dw -1, 0
	.dw 0, -1

nextFrame:
	.dw 0
