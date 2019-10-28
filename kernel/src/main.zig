const std = @import("std");
const builtin = @import("builtin");

const Terminal = @import("text-terminal.zig");
const Multiboot = @import("multiboot.zig");
const VGA = @import("vga.zig");

export var multibootHeader align(4) linksection(".multiboot") = Multiboot.Header.init();

pub fn main() anyerror!void {
    Terminal.clear();
    Terminal.print("Hello, World!\r\n");
    Terminal.setForegroundColor(.lightMagenta);
    Terminal.print("I'm pink!\r");
    Terminal.setForegroundColor(.lightBlue);
    Terminal.print("I'm\r\n");
    Terminal.resetColors();
    // Terminal.print("Multiboot Flags: {}\r\n", @bitCast(MultibootStructure.Flags, val));

    const flags = @ptrCast(*Multiboot.Structure.Flags, &multiboot.flags).*;

    Terminal.print("Multiboot Structure: {*}\r\n", multiboot);
    inline for (@typeInfo(Multiboot.Structure).Struct.fields) |fld| {
        if (comptime !std.mem.eql(u8, comptime fld.name, "flags")) {
            if (@field(flags, fld.name)) {
                Terminal.print("\t{}\t= {}\r\n", fld.name, @field(multiboot, fld.name));
            }
        }
    }

    var vgaMemory = @intToPtr([*]u8, 0xA0000);

    Terminal.print("VGA init...\r\n");
    VGA.init();

    // var rng_engine = std.rand.DefaultPrng.init(0);
    // var rng = &rng_engine.random;

    var time: usize = 0;
    while (true) : (time += 1) {
        var c: u4 = 0;
        var y: usize = 0;
        while (y < 480) : (y += 1) {
            var x: usize = 0;
            while (x < 640) : (x += 1) {
                VGA.setPixel(x, y, c);
                _ = @addWithOverflow(u4, c, @truncate(u4, x + y + x * y + time), &c);
            }
        }
        VGA.swapBuffers();
    }
}

fn kmain() noreturn {
    if (multibootMagic != 0x2BADB002) {
        @panic("System was not bootet with multiboot!");
    }

    main() catch |err| {
        Terminal.setColor(.white, .red);
        Terminal.print("\r\n\r\nmain() returned {}!", err);
    };

    while (true) {}
}

var kernelStack: [8192]u8 align(16) = undefined;

var multiboot: *Multiboot.Structure = undefined;
var multibootMagic: u32 = undefined;

export nakedcc fn _start() noreturn {
    // DO NOT INSERT CODE BEFORE HERE
    // WE MUST NOT MODIFY THE REGISTER CONTENTS
    // BEFORE SAVING THEM TO MEMORY
    multiboot = asm volatile (""
        : [_] "={ebx}" (-> *Multiboot.Structure)
    );
    multibootMagic = asm volatile (""
        : [_] "={eax}" (-> u32)
    );
    // FROM HERE ON WE ARE SAVE

    @newStackCall(kernelStack[0..], kmain);
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    Terminal.setColor(.white, .red);
    Terminal.print("\r\n\r\nKERNEL PANIC:\r\n{}", msg);
    while (true) {}
}
