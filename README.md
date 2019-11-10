# RetrOS

A project that aims to create a fake/virtual console similar
to the PICO-8, LIKO-12 or TIC-80.

## Concept

- The user can program the console via builtin tools
- Projects/Games can be saved/loaded
	- A project can be up to 1440 KiB large
	- Projects can be saved/loaded to/from an extern floppy disk
	- Projects can be stored on an ATA hard disk
		- Uses partition tables!
		- Uses "slots": Every slot contains a full floppy disk image
- User can program its projects via [GASM](#GASM) language

## GASM
The *Game Assembly* language is a fake assembly language that
behaves similar to x86 asm. It supports not only generic
instructions to manipulate memory, but also has special
instructions for the fake console to make programming games
easier.

```asm
init:
	mov r0, 0
	mov [running], 1

Loops r0 until it is 200
.loop:
	cmp r0, 200
	jiz stop

	add r0, 1
	cmp counter
	jmp .loop

stop:
	mov [running], 0
	jmp stop

running:
	.dw 0
```

### Syntax and Semantics

Register Names (32 bit):
- `r0` … `r15`

#### Flags
- `C`: Carry, set when an instruction overflows
- `Z`: Zero, set when an instruction results in zero.

#### Operand Format

- `r0` … `r15` are register names
- decimal or hexadecimal numbers are used as literals
- label names can be used instead of literals for the address of the label
- `[…]` is an indirection and stores/loads from the memory address `…` instead of using `…` as an immediate value. `…` can be any other non-indirect operand.
- `[…+n]` is an indirection similar to `[…]`, but it will offset the address in … by n bytes.

#### Instructions:

Note: `*x` means that `x` may be modified.

| Instruction     | Description |
|-----------------|-------------|
| `mov *dst, src` | copies src to dst |
| `add *dst, val` | adds val to dst |
| `sub *dst, val` | subtracts val from dst |
| `cmp a, b`      | compares a to b and stores result in | flags. Z is set when a==b, C is set when a < b |
| `jmp dst`       | jumps execution to address dst |
| `jnz dst`       | jumps execution to address dst when Z is set |
| `jlz dst`       | jumps execution to address dst when C is set |
| `jgz dst`       | jumps execution to address dst when both Z  and C are not set |
| `jiz dst`       | jumps execution to address dst when Z is not set |
| `shl *dst, cnt` | shifts dst cnt bits to the left |
| `shr *dst, cnt` | shifts dst cnt bits to the right |
| `gettime *dst`  | stores the current system time in ms into dst |
| `setpix x,y,c`  | sets pixel (x,y) to color c |
| `getpix *c,x,y` | gets pixel (x,y) into c |

#### Directives

| Syntax | Description |
|--------|-------------|
| `.def NAME, value` | creates new constant `NAME` that will be replaced with `value` from this line on. `value` can be any number, identifier or register name. |
| `.undef NAME`      | removes a previously defined constant. |
| `.dw a,…`          | stores literal 32bit word a, … at the current position |
| `.align v`         | aligns the current position with v bytes |

#### Labels

- `name:` defines a global label "name"
- `.name:` defines a local label "name" that can only be used/references between to global labels.

## Screenshots

**Rendering text in VGA 256 color mode:**

![](https://mq32.de/public/91d1ab44ba267c5b94563e6d7d308c0232ce964c.png)

**Playing a nice game of snake:**

![](https://mq32.de/public/4367caedb0616bf483852f55b315db3d361bb6aa.png)

## TODO List

- [x] Create bare metal i386 application
- [x] Provide a 16 color VGA driver with 640x480 pixels resolution
- [ ] Provide a keyboard input driver
- [ ] Provide a sound driver
- [ ] Have a simple file system supported
	- [ ] Floppy controller support
	- [ ] ATA support
- [ ] Provide the following editors:
	- [ ] code
	- [ ] sound
	- [ ] image
- [ ] Allow "scripting" via GASM
	- [ ] Write assembler
	- [ ] Write spec
	- [ ] Write documentation




