


all: show-disasm

show-disasm: foo
	ndisasm -b32 $<

foo: foo.asm
	nasm -o $@ $<

.PHONY: show-disasm
