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
    cursor: VGA.Color,
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
    .cursor = 7,
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

var cursorX: usize = 0;
var cursorY: ?*TextLine = null;

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

    cursorY = firstLine;
    cursorX = 0;
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
        var col: usize = 0;
        var cursorCol: usize = 0;
        for (line_text) |c, i| {
            if (col >= 53) // maximum line length
                break;

            if (i <= cursorX) {
                cursorCol = col;
            }

            std.debug.assert(c != '\n');
            if (c == '\t') {
                col = (col + 4) & 0xFFFFC;
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

        if (cursorX == line_text.len and line_text.len > 0) {
            // adjust "end of line"
            cursorCol += 1;
        }

        if (line == cursorY) {
            var y: u3 = 0;
            while (y < 7) : (y += 1) {
                VGA.setPixel(6 * cursorCol, 8 * row + y, colorScheme.cursor);
            }
        }
    }

    VGA.swapBuffers();
}

pub extern fn run() noreturn {
    paint();

    while (true) {
        if (Keyboard.getKey()) |key| {
            const Helper = struct {
                fn navigateUp() void {
                    if (cursorY) |cursor| {
                        if (cursor.previous) |prev| {
                            if (cursorY == firstLine)
                                firstLine = prev;
                            cursorY = prev;
                            cursorX = std.math.min(cursorX, cursorY.?.length);
                        }
                    }
                }

                fn navigateDown() void {
                    var lastLine = firstLine;
                    var i: usize = 0;
                    while (i < 24 and lastLine != null) : (i += 1) {
                        lastLine = lastLine.?.next;
                    }

                    if (cursorY) |cursor| {
                        if (cursor.next) |next| {
                            if (cursorY == lastLine)
                                firstLine = firstLine.?.next;
                            cursorY = next;
                            cursorX = std.math.min(cursorX, cursorY.?.length);
                        }
                    }
                }

                fn navigateLeft() void {
                    if (cursorY) |cursor| {
                        if (cursorX > 0) {
                            cursorX -= 1;
                        } else if (cursor.previous != null) {
                            cursorX = std.math.maxInt(usize);
                            navigateUp();
                        }
                    }
                }

                fn navigateRight() void {
                    if (cursorY) |cursor| {
                        if (cursorX < cursor.length) {
                            cursorX += 1;
                        } else if (cursor.next != null) {
                            cursorX = 0;
                            navigateDown();
                        }
                    }
                }
            };

            if (key.set == .extended0 and key.scancode == 0x48) { // ↑
                Helper.navigateUp();
            } else if (key.set == .extended0 and key.scancode == 0x50) { // ↓
                Helper.navigateDown();
            } else if (key.set == .extended0 and key.scancode == 0x4B) { // ←
                Helper.navigateLeft();
            } else if (key.set == .extended0 and key.scancode == 0x4D) { // →
                Helper.navigateRight();
            } else if (key.set == .default and key.scancode == 14) { // backspace
                if (cursorY) |cursor| {
                    if (cursorX > 0) {
                        std.mem.copy(u8, cursor.text[cursorX - 1 ..], cursor.text[cursorX..]);
                        cursor.length -= 1;
                        cursorX -= 1;
                    } else {
                        if (cursor.previous) |prev| {
                            // merge lines here
                            std.mem.copy(u8, prev.text[prev.length..], cursor.text[0..cursor.length]);

                            cursorX = prev.length;
                            prev.length += cursor.length;

                            prev.next = cursor.next;
                            if (cursor.next) |nx| {
                                nx.previous = prev;
                            }

                            // ZIG BUG!
                            lines.free(cursor);
                            cursorY = prev;

                            if (firstLine == cursor) {
                                firstLine = prev;
                            }
                        } else {
                            // nothing to delete
                        }
                    }
                }
            } else if (key.set == .extended0 and key.scancode == 71) { // Home
                cursorX = 0;
            } else if (key.set == .extended0 and key.scancode == 79) { // End
                if (cursorY) |c| {
                    cursorX = c.length;
                }
            }
            // [kbd:ScancodeSet.extended0/82/P] Ins
            // [kbd:ScancodeSet.extended0/83/P] Del
            // [kbd:ScancodeSet.extended0/73/P] PgUp
            // [kbd:ScancodeSet.extended0/81/P] PgDown
            else if (key.char) |chr| {
                if (chr != '\n') {
                    if (cursorY) |cursor| {
                        if (cursorX < cursor.length) {
                            std.mem.copyBackwards(u8, cursor.text[cursorX + 1 .. cursor.length], cursor.text[cursorX .. std.math.max(1, cursor.length) - 1]);
                        }
                        cursor.text[cursorX] = chr;
                        cursor.length += 1;
                        cursorX += 1;
                    }
                }
            }
            paint();
        }

        // Sleep and wait for interrupt
        asm volatile ("hlt");
    }
}
