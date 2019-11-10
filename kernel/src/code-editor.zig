const std = @import("std");
const Keyboard = @import("keyboard.zig");
const VGA = @import("vga.zig");
const TextTerminal = @import("text-terminal.zig");
const BlockAllocator = @import("block-allocator.zig").BlockAllocator;

const Glyph = packed struct {
    const This = @This();

    rows: [8]u8,

    fn getPixel(this: This, x: u3, y: u3) u1 {
        return @truncate(u1, (this.rows[y] >> x) & 1);
    }
};
const stdfont = @bitCast([128]Glyph, @embedFile("stdfont.bin"));

const TextLine = struct {
    previous: ?*TextLine,
    next: ?*TextLine,
    text: [120]u8,
    length: usize,
};

var lines = BlockAllocator(TextLine, 4096).init();

var firstLine: ?*TextLine = null;

pub fn load(source: []const u8) !void {
    lines.reset();
    firstLine = null;

    var it = std.mem.separate(source, "\n");
    var previousLine: ?*TextLine = null;
    while (it.next()) |line| {
        var tl = try lines.alloc();

        std.mem.copy(u8, tl.text[0..], line);
        tl.length = line.len;
        tl.next = null;
        tl.previous = previousLine;

        if (previousLine) |prev| {
            prev.next = tl;
        }

        previousLine = tl;

        if (firstLine == null) {
            firstLine = tl;
        }
    }
}

fn paint() void {
    const font = stdfont;
    const background = 0x00;
    const foreground = 0x1F;

    VGA.clear(background);

    var row: usize = 0;

    var line_iterator = firstLine;
    while (line_iterator) |line| : ({
        line_iterator = line.next;
        row += 1;
    }) {
        if (row >= 25)
            break;

        var col: usize = 0;

        for (line.text[0..line.length]) |c| {
            std.debug.assert(c != '\n');
            if (c == '\t') {
                col = (col + 4) & 0xFFFF6;
                continue;
            }

            const safe_c = if (c < 128) c else '?';
            var y: u3 = 0;
            while (y < 7) : (y += 1) {
                var x: u3 = 0;
                while (x < 6) : (x += 1) {
                    VGA.setPixel(6 * col + x, 8 * row + y, switch (font[safe_c].getPixel(x, y)) {
                        0 => VGA.Color(background),
                        1 => VGA.Color(foreground),
                    });
                }
            }
            col += 1;
        }
    }

    VGA.swapBuffers();
}

pub extern fn run() noreturn {
    paint();

    while (true) {
        if (Keyboard.getKey()) |key| {
            if (key.char) |chr| {
                // Terminal.print("{c}", chr);
            }
        }

        asm volatile ("hlt");
    }
}
