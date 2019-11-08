
QEMU_FLAGS+=\
	-serial stdio \
	-vga std \
	-no-reboot \
	-no-shutdown \
	-m 64M \
	-d guest_errors#,int,cpu_reset

ZIG_FLAGS+=#-Drelease-fast=true

all: boot.img

run: boot.img
	qemu-system-i386 $(QEMU_FLAGS) -fda $<

boot.img: zig-cache/bin/kernel syslinux.cfg
	strip $<
	fallocate -l 1440K $@
	mkfs.vfat -n RETROS $@
	syslinux -a $@
	mmd -i $@ ::/syslinux
	mcopy -i $@ /usr/lib/syslinux/bios/{syslinux,mboot,libcom32}.c32 ::/syslinux
	mcopy -i $@ syslinux.cfg ::/syslinux
	mcopy -i $@ zig-cache/bin/kernel ::

zig-cache/bin/kernel:
	zig build $(ZIG_FLAGS)

zig-cache/bin/assembler:
	zig build # -Drelease-fast=true

assembler-test: ./zig-cache/bin/assembler
	./zig-cache/bin/assembler
	ndisasm -b32 -o 0x200000 /tmp/develop.gasm | head -n200
	
.PHONY: zig-cache/bin/kernel zig-cache/bin/assembler assembler-test
