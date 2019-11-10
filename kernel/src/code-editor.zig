const std = @import("std");
const Keyboard = @import("keyboard.zig");
const VGA = @import("vga.zig");
const TextTerminal = @import("text-terminal.zig");
const BlockAllocator = @import("block-allocator.zig").BlockAllocator;

const ColorScheme = struct {
    background: VGA.Color,
    text: VGA.Color,
    comment: VGA.Color,
    mnemonic: VGA.Color,
    indirection: VGA.Color,
    register: VGA.Color,
    label: VGA.Color,
    directive: VGA.Color,
};

pub var colorScheme = ColorScheme{
    .background = 0,
    .text = 7,
    .comment = 2,
    .mnemonic = 6,
    .indirection = 5,
    .register = 3,
    .label = 30,
    .directive = 9,
};

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

    VGA.clear(colorScheme.background);

    var row: usize = 0;

    var line_iterator = firstLine;
    while (line_iterator) |line| : ({
        line_iterator = line.next;
        row += 1;
    }) {
        if (row >= 25)
            break;

        var col: usize = 0;

        var line_text = line.text[0..line.length];

        var label_pos = std.mem.indexOf(u8, line_text, ":");

        const TextType = enum {
            background,
            text,
            comment,
            mnemonic,
            indirection,
            register,
            label,
            directive,
        };

        var highlighting: TextType = .text;
        var resetHighlighting = false;
        var hadMnemonic = false;

        var pal: VGA.Color = 0;
        for (line_text) |c, i| {
            if (col >= 53) // maximum line length
                break;

            std.debug.assert(c != '\n');
            if (c == '\t') {
                col = (col + 4) & 0xFFFF6;
                continue;
            }

            if (highlighting != .comment) {
                if (resetHighlighting) {
                    highlighting = .text;
                }

                if (c == '#') {
                    highlighting = .comment;
                } else if (c == ' ') {
                    if (highlighting == .mnemonic) {
                        hadMnemonic = true;
                    }
                    highlighting = .text;
                } else {
                    if (label_pos) |pos| {
                        if (i <= pos) {
                            highlighting = .label;
                        }
                    }
                    if (c == '[' or c == ']') {
                        highlighting = .indirection;
                        resetHighlighting = true;
                    } else if (c == '.') {
                        highlighting = .directive;
                        hadMnemonic = true; // prevent mnemonic highlighting
                    } else if (highlighting == .text and !hadMnemonic and ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))) {
                        highlighting = .mnemonic;
                    }
                }
            }

            const safe_c = if (c < 128) c else '?';
            var y: u3 = 0;
            while (y < 7) : (y += 1) {
                var x: u3 = 0;
                while (x < 6) : (x += 1) {
                    if (font[safe_c].getPixel(x, y) == 1) {
                        VGA.setPixel(6 * col + x, 8 * row + y, switch (highlighting) {
                            .background => colorScheme.background,
                            .text => colorScheme.text,
                            .comment => colorScheme.comment,
                            .mnemonic => colorScheme.mnemonic,
                            .indirection => colorScheme.indirection,
                            .register => colorScheme.register,
                            .label => colorScheme.label,
                            .directive => colorScheme.directive,
                            else => colorScheme.text,
                        });
                    }
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
            if (key.set == .extended0 and key.scancode == 0x48) { // ↑
                if (firstLine) |line| {
                    if (line.previous) |prev| {
                        firstLine = prev;
                        paint();
                    }
                }
            } else if (key.set == .extended0 and key.scancode == 0x50) { // ↓
                if (firstLine) |line| {
                    if (line.next) |next| {
                        firstLine = next;
                        paint();
                    }
                }
            }

            if (key.char) |chr| {
                // Terminal.print("{c}", chr);
            }
        }

        asm volatile ("hlt");
    }
}
