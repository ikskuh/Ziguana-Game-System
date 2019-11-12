
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
	qemu-system-i386 $(QEMU_FLAGS) -hda $< | aux/stacktrace_to_line.sh

boot.img: zig-cache/bin/kernel syslinux.cfg
	fallocate -l 20M $@
	mkfs.vfat -n RETROS $@
	syslinux -a $@
	mmd -i $@ ::/syslinux
	mcopy -i $@ /usr/lib/syslinux/bios/{syslinux,mboot,libcom32}.c32 ::/syslinux
	mcopy -i $@ syslinux.cfg ::/syslinux
	mcopy -i $@ zig-cache/bin/kernel ::

floppy.img: zig-cache/bin/kernel syslinux.cfg src/stdfont.bin src/stdkbd_default.bin src/splashscreen.bin
	zig build -Drelease-small=true
	strip $<

	@echo "Kernel Size: " `wc -c zig-cache/bin/kernel`

	fallocate -l 1440K $@
	mkfs.vfat -n RETROS $@
	syslinux -a $@
	mmd -i $@ ::/syslinux
	mcopy -i $@ /usr/lib/syslinux/bios/{syslinux,mboot,libcom32}.c32 ::/syslinux
	mcopy -i $@ syslinux.cfg ::/syslinux
	mcopy -i $@ zig-cache/bin/kernel ::

zig-cache/bin/kernel: src/stdfont.bin src/stdkbd_default.bin src/splashscreen.bin
	zig build $(ZIG_FLAGS)

zig-cache/bin/assembler:
	zig build # -Drelease-fast=true

src/stdfont.bin: ../data/font_8x8.png aux/fontconv.exe
	mono aux/fontconv.exe $< $@

src/stdkbd_default.bin: ../data/kbd_ger_std.txt aux/mkkeymap.exe
	mono aux/mkkeymap.exe $< $@

src/splashscreen.bin: ../data/splashlogo.png aux/mkbitmap.exe
	mono aux/mkbitmap.exe $< $@

assembler-test: ./zig-cache/bin/assembler
	./zig-cache/bin/assembler
	ndisasm -b32 -o 0x200000 /tmp/develop.gasm | head -n200

aux/%.exe: aux/%.cs
	mcs -reference:System.Drawing.dll -out:$@ $^

.PHONY: zig-cache/bin/kernel zig-cache/bin/assembler assembler-test
