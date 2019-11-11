const std = @import("std");
const Keyboard = @import("keyboard.zig");
const VGA = @import("vga.zig");
const TextTerminal = @import("text-terminal.zig");
const BlockAllocator = @import("block-allocator.zig").BlockAllocator;
const Timer = @import("timer.zig");
const TextPainter = @import("text-painter.zig");

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
    .text = 1,
    .comment = 2,
    .mnemonic = 3,
    .indirection = 4,
    .register = 5,
    .label = 6,
    .directive = 7,
    .cursor = 8,
};

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

/// Saves all text lines to the given slice.
/// Returns the portion of the slice actually written.
pub fn saveTo(target: []u8) ![]u8 {
    var start = firstLine;
    while (start) |s| {
        if (s.previous != null) {
            start = s.previous;
        } else {
            break;
        }
    }

    var buffer = target;
    var lenWritten: usize = 0;
    while (start) |node| {
        if (buffer.len < (node.length + 1))
            return error.InputBufferTooSmall;
        std.mem.copy(u8, buffer, node.text[0..node.length]);
        buffer[node.length] = '\n';
        buffer = buffer[node.length + 1 ..];
        lenWritten += node.length + 1;
        start = node.next;
    }

    return target[0..lenWritten];
}

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

            TextPainter.drawChar(@intCast(isize, 1 + 6 * col), @intCast(isize, 8 * row), c, switch (highlighting) {
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

            col += 1;
        }

        if (cursorX == line_text.len and line_text.len > 0) {
            // adjust "end of line"
            cursorCol += 1;
        }

        if (line == cursorY and (Timer.ticks % 1000 > 500)) {
            var y: u3 = 0;
            while (y < 7) : (y += 1) {
                VGA.setPixel(6 * cursorCol, 8 * row + y, colorScheme.cursor);
            }
        }
    }

    VGA.swapBuffers();
}

pub extern fn run() noreturn {

    // .background = 0,
    // .text = 1,
    // .comment = 2,
    // .mnemonic = 3,
    // .indirection = 4,
    // .register = 5,
    // .label = 6,
    // .directive = 7,
    // .cursor = 8,
    VGA.loadPalette(comptime [_]VGA.RGB{
        VGA.RGB.parse("#000000") catch unreachable, //  0
        VGA.RGB.parse("#CCCCCC") catch unreachable, //  1
        VGA.RGB.parse("#346524") catch unreachable, //  2
        VGA.RGB.parse("#d27d2c") catch unreachable, //  3
        VGA.RGB.parse("#d27d2c") catch unreachable, //  4
        VGA.RGB.parse("#30346d") catch unreachable, //  5
        VGA.RGB.parse("#d04648") catch unreachable, //  6
        VGA.RGB.parse("#597dce") catch unreachable, //  7
        VGA.RGB.parse("#ffffff") catch unreachable, //  8
    });

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
            } else if (key.set == .default and key.scancode == 28) { // Return
                if (cursorY) |cursor| {
                    var cursor_set_pos: enum {
                        tl,
                        cursor,
                    } = undefined;
                    var tl = lines.alloc() catch @panic("out of memory!");
                    if (cursorX == 0) {
                        // trivial case: front insert
                        tl.previous = cursor.previous;
                        tl.next = cursor;
                        tl.length = 0;
                        if (firstLine == cursor) {
                            firstLine = tl;
                        }
                    } else if (cursorX == cursor.length) {
                        // trivial case: back insert
                        tl.previous = cursor;
                        tl.next = cursor.next;
                        tl.length = 0;
                        cursor_set_pos = .tl;
                    } else {
                        // complex case: middle insert
                        tl.previous = cursor;
                        tl.next = cursor.next;

                        tl.length = cursor.length - cursorX;
                        cursor.length = cursorX;

                        std.mem.copy(u8, tl.text[0..], cursor.text[cursorX..]);
                        cursor_set_pos = .tl;
                    }

                    if (tl.previous) |prev| {
                        prev.next = tl;
                    }
                    if (tl.next) |next| {
                        next.previous = tl;
                    }
                    switch (cursor_set_pos) {
                        .tl => {
                            cursorY = tl;
                        },
                        .cursor => {
                            cursorY = cursor;
                        },
                    }
                    cursorX = 0;
                }
            } else if (key.set == .extended0 and key.scancode == 71) { // Home
                cursorX = 0;
            } else if (key.set == .extended0 and key.scancode == 79) { // End
                if (cursorY) |c| {
                    cursorX = c.length;
                }
            } else if (key.set == .extended0 and key.scancode == 83) { // Del
                if (cursorY) |cursor| {
                    if (cursorX == cursor.length) {
                        // merge two lines
                        if (cursor.next) |next| {
                            std.mem.copy(u8, cursor.text[cursor.length..], next.text[0..next.length]);
                            cursor.length += next.length;

                            if (next.next) |nxt| {
                                nxt.previous = cursor;
                            }

                            // BAH, FOOTGUNS
                            lines.free(next);
                            // BAH, MORE FOOTGUNS
                            cursor.next = next.next;
                        }
                    } else {
                        // erase character
                        std.mem.copy(u8, cursor.text[cursorX .. cursor.length - 1], cursor.text[cursorX + 1 .. cursor.length]);
                        cursor.length -= 1;
                    }
                }
            }
            // [kbd:ScancodeSet.extended0/82/P] Ins
            // [kbd:ScancodeSet.extended0/73/P] PgUp
            // [kbd:ScancodeSet.extended0/81/P] PgDown
            else if (key.char) |chr| {
                std.debug.assert(chr != '\n');
                if (cursorY) |cursor| {
                    cursor.length += 1;
                    if (cursorX < cursor.length) {
                        std.mem.copyBackwards(u8, cursor.text[cursorX + 1 .. cursor.length], cursor.text[cursorX .. cursor.length - 1]);
                    }
                    cursor.text[cursorX] = chr;
                    cursorX += 1;
                }
            }
        }

        // Sleep and wait for interrupt
        asm volatile ("hlt");
        paint();
    }
}
