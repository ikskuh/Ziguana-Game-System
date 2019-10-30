
QEMU_FLAGS+=\
	-serial stdio \
	-vga std \
	-no-reboot \
	-no-shutdown \
	-m 64M \
	-d cpu_reset,guest_errors,int

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
	zig build # -Drelease-fast=true

	
.PHONY: zig-cache/bin/kernel
