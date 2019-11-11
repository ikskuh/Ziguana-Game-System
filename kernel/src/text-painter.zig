const VGA = @import("vga.zig");

const Glyph = packed struct {
    const This = @This();

    rows: [8]u8,

    fn getPixel(this: This, x: u3, y: u3) u1 {
        return @truncate(u1, (this.rows[y] >> x) & 1);
    }
};

const stdfont = @bitCast([128]Glyph, @embedFile("stdfont.bin"));

pub fn drawChar(x: isize, y: isize, char: u8, color: VGA.Color) void {
    if (x <= -6 or y <= -6 or x >= VGA.width or y >= VGA.height)
        return;

    const safe_c = if (char < 128) char else 0x1F;
    var dy: u3 = 0;
    while (dy < 7) : (dy += 1) {
        var dx: u3 = 0;
        while (dx < 6) : (dx += 1) {
            if (VGA.isInBounds(x + @as(isize, dx), y + @as(isize, dy))) {
                if (stdfont[safe_c].getPixel(dx, dy) == 1) {
                    VGA.setPixel(@intCast(usize, x) + dx, @intCast(usize, y) + dy, color);
                }
            }
        }
    }
}

pub const PaintOptions = struct {
    color: VGA.Color = 1,
    horizontalAlignment: enum {
        left,
        middle,
        right,
    } = .left,
    verticalAlignment: enum {
        top,
        middle,
        bottom,
    } = .top,
};

/// Draws a string with formatting (alignment)
pub fn drawString(x: isize, y: isize, text: []const u8, options: PaintOptions) void {
    const startX = switch (options.horizontalAlignment) {
        .left => x,
        .middle => x - @intCast(isize, 6 * text.len / 2),
        .right => x - @intCast(isize, 6 * text.len),
    };
    const startY = switch (options.verticalAlignment) {
        .top => y,
        .middle => y + 4,
        .bottom => y + 8,
    };
    for (text) |c, i| {
        const left = startX + @intCast(isize, 6 * i);
        if (left <= -6)
            continue;
        const top = startY;

        drawChar(left, top, c, options.color);
    }
}
