

all: boot.img

run: boot.img
	qemu-system-i386 \
		-hda $< \
		-serial stdio \
		-vga std

boot.img: zig-cache/bin/kernel syslinux.cfg
	fallocate -l 32M $@
	mkfs.vfat -n RETROS $@
	syslinux -a $@
	mmd -i $@ ::/syslinux
	mcopy -i $@ /usr/lib/syslinux/bios/* ::/syslinux
	mcopy -i $@ syslinux.cfg ::/syslinux
	mcopy -i $@ zig-cache/bin/kernel ::

zig-cache/bin/kernel:
	zig build
	
.PHONY: zig-cache/bin/kernel
