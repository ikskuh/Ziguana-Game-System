
QEMU_FLAGS+=\
	-serial stdio \
	-vga std \
	-no-reboot \
	-no-shutdown \
	-m 64M \
	-d cpu_reset,guest_errors

ZIG_FLAGS=#-Drelease-fast=true

all: boot.img

run: boot.img
	qemu-system-i386 $(QEMU_FLAGS) -hda $<

boot.img: zig-cache/bin/kernel syslinux.cfg
	fallocate -l 32M $@
	mkfs.vfat -n RETROS $@
	syslinux -a $@
	mmd -i $@ ::/syslinux
	mcopy -i $@ /usr/lib/syslinux/bios/* ::/syslinux
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
