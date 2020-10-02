const std = @import("std");
const io = @import("io.zig");
const Terminal = @import("text-terminal.zig");

fn outportb(port: u16, val: u8) void {
    io.out(u8, port, val);
}

fn inportb(port: u16) u8 {
    return io.in(u8, port);
}

pub const VgaMode = enum {
    mode320x200,
    mode640x480,
};

pub const mode = if (@hasDecl(@import("root"), "vga_mode")) @import("root").vga_mode else VgaMode.mode320x200;

pub const Color = switch (mode) {
    .mode320x200 => u8,
    .mode640x480 => u4,
};

pub const width = switch (mode) {
    .mode320x200 => 320,
    .mode640x480 => 640,
};

pub const height = switch (mode) {
    .mode320x200 => 200,
    .mode640x480 => 480,
};

pub fn isInBounds(x: isize, y: isize) bool {
    return x >= 0 and y >= 0 and x < width and y < height;
}

fn write_regs(regs: [61]u8) void {
    var index: usize = 0;
    var i: u8 = 0;

    // write MISCELLANEOUS reg
    outportb(VGA_MISC_WRITE, regs[index]);
    index += 1;

    // write SEQUENCER regs
    i = 0;
    while (i < VGA_NUM_SEQ_REGS) : (i += 1) {
        outportb(VGA_SEQ_INDEX, i);
        outportb(VGA_SEQ_DATA, regs[index]);
        index += 1;
    }

    // unlock CRTC registers
    outportb(VGA_CRTC_INDEX, 0x03);
    outportb(VGA_CRTC_DATA, inportb(VGA_CRTC_DATA) | 0x80);
    outportb(VGA_CRTC_INDEX, 0x11);
    outportb(VGA_CRTC_DATA, inportb(VGA_CRTC_DATA) & ~@as(u8, 0x80));

    // make sure they remain unlocked
    // TODO: Reinsert again
    // regs[0x03] |= 0x80;
    // regs[0x11] &= ~0x80;

    // write CRTC regs

    i = 0;
    while (i < VGA_NUM_CRTC_REGS) : (i += 1) {
        outportb(VGA_CRTC_INDEX, i);
        outportb(VGA_CRTC_DATA, regs[index]);
        index += 1;
    }
    // write GRAPHICS CONTROLLER regs
    i = 0;
    while (i < VGA_NUM_GC_REGS) : (i += 1) {
        outportb(VGA_GC_INDEX, i);
        outportb(VGA_GC_DATA, regs[index]);
        index += 1;
    }
    // write ATTRIBUTE CONTROLLER regs
    i = 0;
    while (i < VGA_NUM_AC_REGS) : (i += 1) {
        _ = inportb(VGA_INSTAT_READ);
        outportb(VGA_AC_INDEX, i);
        outportb(VGA_AC_WRITE, regs[index]);
        index += 1;
    }
    // lock 16-color palette and unblank display
    _ = inportb(VGA_INSTAT_READ);
    outportb(VGA_AC_INDEX, 0x20);
}

pub fn setPlane(plane: u2) void {
    const pmask: u8 = u8(1) << plane;

    // set read plane
    outportb(VGA_GC_INDEX, 4);
    outportb(VGA_GC_DATA, plane);
    // set write plane
    outportb(VGA_SEQ_INDEX, 2);
    outportb(VGA_SEQ_DATA, pmask);
}

pub fn init() void {
    switch (mode) {
        .mode320x200 => write_regs(g_320x200x256),
        .mode640x480 => write_regs(g_640x480x16),
    }

    // write_regs(g_320x200x256);
}

fn get_fb_seg() [*]volatile u8 {
    outportb(VGA_GC_INDEX, 6);
    const seg = (inportb(VGA_GC_DATA) >> 2) & 3;
    return @intToPtr([*]volatile u8, switch (@truncate(u2, seg)) {
        0, 1 => @as(u32, 0xA0000),
        2 => @as(u32, 0xB0000),
        3 => @as(u32, 0xB8000),
    });
}

fn vpokeb(off: usize, val: u8) void {
    get_fb_seg()[off] = val;
}

fn vpeekb(off: usize) u8 {
    return get_fb_seg()[off];
}

pub fn setPixelDirect(x: usize, y: usize, c: Color) void {
    switch (mode) {
        .mode320x200 => {
            // setPlane(@truncate(u2, 0));
            var segment = get_fb_seg();
            segment[320 * y + x] = c;
        },

        .mode640x480 => {
            const wd_in_bytes = 640 / 8;
            const off = wd_in_bytes * y + x / 8;
            const px = @truncate(u3, x & 7);
            var mask: u8 = u8(0x80) >> px;
            var pmask: u8 = 1;

            comptime var p: usize = 0;
            inline while (p < 4) : (p += 1) {
                setPlane(@truncate(u2, p));
                var segment = get_fb_seg();
                const src = segment[off];
                segment[off] = if ((pmask & c) != 0) src | mask else src & ~mask;
                pmask <<= 1;
            }
        },
    }
}

var backbuffer: [height][width]Color = undefined;

pub fn clear(c: Color) void {
    for (backbuffer) |*row| {
        for (row) |*pixel| {
            pixel.* = c;
        }
    }
}

pub fn setPixel(x: usize, y: usize, c: Color) void {
    backbuffer[y][x] = c;
}

pub fn getPixel(x: usize, y: usize) Color {
    return backbuffer[y][x];
}

pub fn swapBuffers() void {
    @setRuntimeSafety(false);
    @setCold(false);

    switch (mode) {
        .mode320x200 => {
            @intToPtr(*[height][width]Color, 0xA0000).* = backbuffer;
        },
        .mode640x480 => {

            // const bytes_per_line = 640 / 8;
            var plane: usize = 0;
            while (plane < 4) : (plane += 1) {
                const plane_mask: u8 = u8(1) << @truncate(u3, plane);
                setPlane(@truncate(u2, plane));

                var segment = get_fb_seg();

                var offset: usize = 0;

                var y: usize = 0;
                while (y < 480) : (y += 1) {
                    var x: usize = 0;
                    while (x < 640) : (x += 8) {
                        // const offset = bytes_per_line * y + (x / 8);
                        var bits: u8 = 0;

                        // unroll for maximum fastness
                        comptime var px: usize = 0;
                        inline while (px < 8) : (px += 1) {
                            const mask = u8(0x80) >> px;
                            const index = backbuffer[y][x + px];
                            if ((index & plane_mask) != 0) {
                                bits |= mask;
                            }
                        }

                        segment[offset] = bits;
                        offset += 1;
                    }
                }
            }
        },
    }
}

pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn init(r: u8, g: u8, b: u8) RGB {
        return RGB{
            .r = r,
            .g = g,
            .b = b,
        };
    }

    pub fn parse(rgb: []const u8) !RGB {
        if (rgb.len != 7) return error.InvalidLength;
        if (rgb[0] != '#') return error.InvalidFormat;
        return RGB{
            .r = try std.fmt.parseInt(u8, rgb[1..3], 16),
            .g = try std.fmt.parseInt(u8, rgb[3..5], 16),
            .b = try std.fmt.parseInt(u8, rgb[5..7], 16),
        };
    }
};

const PALETTE_INDEX = 0x03c8;
const PALETTE_DATA = 0x03c9;

// see: http://www.brackeen.com/vga/source/bc31/palette.c.html
pub fn loadPalette(palette: []const RGB) void {
    io.out(u8, PALETTE_INDEX, 0); // tell the VGA that palette data is coming.
    for (palette) |rgb| {
        io.out(u8, PALETTE_DATA, rgb.r >> 2); // write the data
        io.out(u8, PALETTE_DATA, rgb.g >> 2);
        io.out(u8, PALETTE_DATA, rgb.b >> 2);
    }
}

pub fn setPaletteEntry(entry: u8, color: RGB) void {
    io.out(u8, PALETTE_INDEX, entry); // tell the VGA that palette data is coming.
    io.out(u8, PALETTE_DATA, color.r >> 2); // write the data
    io.out(u8, PALETTE_DATA, color.g >> 2);
    io.out(u8, PALETTE_DATA, color.b >> 2);
}

// see: http://www.brackeen.com/vga/source/bc31/palette.c.html
pub fn waitForVSync() void {
    const INPUT_STATUS = 0x03da;
    const VRETRACE = 0x08;

    // wait until done with vertical retrace
    while ((io.in(u8, INPUT_STATUS) & VRETRACE) != 0) {}
    // wait until done refreshing
    while ((io.in(u8, INPUT_STATUS) & VRETRACE) == 0) {}
}

const VGA_AC_INDEX = 0x3C0;
const VGA_AC_WRITE = 0x3C0;
const VGA_AC_READ = 0x3C1;
const VGA_MISC_WRITE = 0x3C2;
const VGA_SEQ_INDEX = 0x3C4;
const VGA_SEQ_DATA = 0x3C5;
const VGA_DAC_READ_INDEX = 0x3C7;
const VGA_DAC_WRITE_INDEX = 0x3C8;
const VGA_DAC_DATA = 0x3C9;
const VGA_MISC_READ = 0x3CC;
const VGA_GC_INDEX = 0x3CE;
const VGA_GC_DATA = 0x3CF;
//            COLOR emulation        MONO emulation
const VGA_CRTC_INDEX = 0x3D4; // 0x3B4
const VGA_CRTC_DATA = 0x3D5; // 0x3B5
const VGA_INSTAT_READ = 0x3DA;

const VGA_NUM_SEQ_REGS = 5;
const VGA_NUM_CRTC_REGS = 25;
const VGA_NUM_GC_REGS = 9;
const VGA_NUM_AC_REGS = 21;
const VGA_NUM_REGS = (1 + VGA_NUM_SEQ_REGS + VGA_NUM_CRTC_REGS + VGA_NUM_GC_REGS + VGA_NUM_AC_REGS);

const g_40x25_text = [_]u8{
    // MISC
    0x67,
    // SEQ
    0x03,
    0x08,
    0x03,
    0x00,
    0x02,
    // CRTC
    0x2D,
    0x27,
    0x28,
    0x90,
    0x2B,
    0xA0,
    0xBF,
    0x1F,
    0x00,
    0x4F,
    0x0D,
    0x0E,
    0x00,
    0x00,
    0x00,
    0xA0,
    0x9C,
    0x8E,
    0x8F,
    0x14,
    0x1F,
    0x96,
    0xB9,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x10,
    0x0E,
    0x00,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x0C,
    0x00,
    0x0F,
    0x08,
    0x00,
};

const g_40x50_text = [_]u8{
    // MISC
    0x67,
    // SEQ
    0x03,
    0x08,
    0x03,
    0x00,
    0x02,
    // CRTC
    0x2D,
    0x27,
    0x28,
    0x90,
    0x2B,
    0xA0,
    0xBF,
    0x1F,
    0x00,
    0x47,
    0x06,
    0x07,
    0x00,
    0x00,
    0x04,
    0x60,
    0x9C,
    0x8E,
    0x8F,
    0x14,
    0x1F,
    0x96,
    0xB9,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x10,
    0x0E,
    0x00,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x0C,
    0x00,
    0x0F,
    0x08,
    0x00,
};

const g_80x25_text = [_]u8{
    // MISC
    0x67,
    // SEQ
    0x03,
    0x00,
    0x03,
    0x00,
    0x02,
    // CRTC
    0x5F,
    0x4F,
    0x50,
    0x82,
    0x55,
    0x81,
    0xBF,
    0x1F,
    0x00,
    0x4F,
    0x0D,
    0x0E,
    0x00,
    0x00,
    0x00,
    0x50,
    0x9C,
    0x0E,
    0x8F,
    0x28,
    0x1F,
    0x96,
    0xB9,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x10,
    0x0E,
    0x00,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x0C,
    0x00,
    0x0F,
    0x08,
    0x00,
};

const g_80x50_text = [_]u8{
    // MISC
    0x67,
    // SEQ
    0x03,
    0x00,
    0x03,
    0x00,
    0x02,
    // CRTC
    0x5F,
    0x4F,
    0x50,
    0x82,
    0x55,
    0x81,
    0xBF,
    0x1F,
    0x00,
    0x47,
    0x06,
    0x07,
    0x00,
    0x00,
    0x01,
    0x40,
    0x9C,
    0x8E,
    0x8F,
    0x28,
    0x1F,
    0x96,
    0xB9,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x10,
    0x0E,
    0x00,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x0C,
    0x00,
    0x0F,
    0x08,
    0x00,
};

const g_90x30_text = [_]u8{
    // MISC
    0xE7,
    // SEQ
    0x03,
    0x01,
    0x03,
    0x00,
    0x02,
    // CRTC
    0x6B,
    0x59,
    0x5A,
    0x82,
    0x60,
    0x8D,
    0x0B,
    0x3E,
    0x00,
    0x4F,
    0x0D,
    0x0E,
    0x00,
    0x00,
    0x00,
    0x00,
    0xEA,
    0x0C,
    0xDF,
    0x2D,
    0x10,
    0xE8,
    0x05,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x10,
    0x0E,
    0x00,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x0C,
    0x00,
    0x0F,
    0x08,
    0x00,
};

const g_90x60_text = [_]u8{
    // MISC
    0xE7,
    // SEQ
    0x03,
    0x01,
    0x03,
    0x00,
    0x02,
    // CRTC
    0x6B,
    0x59,
    0x5A,
    0x82,
    0x60,
    0x8D,
    0x0B,
    0x3E,
    0x00,
    0x47,
    0x06,
    0x07,
    0x00,
    0x00,
    0x00,
    0x00,
    0xEA,
    0x0C,
    0xDF,
    0x2D,
    0x08,
    0xE8,
    0x05,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x10,
    0x0E,
    0x00,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x0C,
    0x00,
    0x0F,
    0x08,
    0x00,
};
// ****************************************************************************
// VGA REGISTER DUMPS FOR VARIOUS GRAPHICS MODES
// ****************************************************************************
const g_640x480x2 = [_]u8{
    // MISC
    0xE3,
    // SEQ
    0x03,
    0x01,
    0x0F,
    0x00,
    0x06,
    // CRTC
    0x5F,
    0x4F,
    0x50,
    0x82,
    0x54,
    0x80,
    0x0B,
    0x3E,
    0x00,
    0x40,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xEA,
    0x0C,
    0xDF,
    0x28,
    0x00,
    0xE7,
    0x04,
    0xE3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x05,
    0x0F,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x01,
    0x00,
    0x0F,
    0x00,
    0x00,
};

//****************************************************************************
// *** NOTE: the mode described by g_320x200x4[]
// is different from BIOS mode 05h in two ways:
// - Framebuffer is at A000:0000 instead of B800:0000
// - Framebuffer is linear (no screwy line-by-line CGA addressing)
// ****************************************************************************
const g_320x200x4 = [_]u8{
    // MISC
    0x63,
    // SEQ
    0x03,
    0x09,
    0x03,
    0x00,
    0x02,
    // CRTC
    0x2D,
    0x27,
    0x28,
    0x90,
    0x2B,
    0x80,
    0xBF,
    0x1F,
    0x00,
    0x41,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x9C,
    0x0E,
    0x8F,
    0x14,
    0x00,
    0x96,
    0xB9,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x30,
    0x02,
    0x00,
    0xFF,
    // AC
    0x00,
    0x13,
    0x15,
    0x17,
    0x02,
    0x04,
    0x06,
    0x07,
    0x10,
    0x11,
    0x12,
    0x13,
    0x14,
    0x15,
    0x16,
    0x17,
    0x01,
    0x00,
    0x03,
    0x00,
    0x00,
};

const g_640x480x16 = [_]u8{
    // MISC
    0xE3,
    // SEQ
    0x03,
    0x01,
    0x08,
    0x00,
    0x06,
    // CRTC
    0x5F,
    0x4F,
    0x50,
    0x82,
    0x54,
    0x80,
    0x0B,
    0x3E,
    0x00,
    0x40,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xEA,
    0x0C,
    0xDF,
    0x28,
    0x00,
    0xE7,
    0x04,
    0xE3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x03,
    0x00,
    0x05,
    0x0F,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x14,
    0x07,
    0x38,
    0x39,
    0x3A,
    0x3B,
    0x3C,
    0x3D,
    0x3E,
    0x3F,
    0x01,
    0x00,
    0x0F,
    0x00,
    0x00,
};

const g_720x480x16 = [_]u8{
    // MISC
    0xE7,
    // SEQ
    0x03,
    0x01,
    0x08,
    0x00,
    0x06,
    // CRTC
    0x6B,
    0x59,
    0x5A,
    0x82,
    0x60,
    0x8D,
    0x0B,
    0x3E,
    0x00,
    0x40,
    0x06,
    0x07,
    0x00,
    0x00,
    0x00,
    0x00,
    0xEA,
    0x0C,
    0xDF,
    0x2D,
    0x08,
    0xE8,
    0x05,
    0xE3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x03,
    0x00,
    0x05,
    0x0F,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x01,
    0x00,
    0x0F,
    0x00,
    0x00,
};

const g_320x200x256 = [_]u8{
    // MISC
    0x63,
    // SEQ
    0x03,
    0x01,
    0x0F,
    0x00,
    0x0E,
    // CRTC
    0x5F,
    0x4F,
    0x50,
    0x82,
    0x54,
    0x80,
    0xBF,
    0x1F,
    0x00,
    0x41,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x9C,
    0x0E,
    0x8F,
    0x28,
    0x40,
    0x96,
    0xB9,
    0xA3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x40,
    0x05,
    0x0F,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x41,
    0x00,
    0x0F,
    0x00,
    0x00,
};

const g_320x200x256_modex = [_]u8{
    // MISC
    0x63,
    // SEQ
    0x03,
    0x01,
    0x0F,
    0x00,
    0x06,
    // CRTC
    0x5F,
    0x4F,
    0x50,
    0x82,
    0x54,
    0x80,
    0xBF,
    0x1F,
    0x00,
    0x41,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x9C,
    0x0E,
    0x8F,
    0x28,
    0x00,
    0x96,
    0xB9,
    0xE3,
    0xFF,
    // GC
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x40,
    0x05,
    0x0F,
    0xFF,
    // AC
    0x00,
    0x01,
    0x02,
    0x03,
    0x04,
    0x05,
    0x06,
    0x07,
    0x08,
    0x09,
    0x0A,
    0x0B,
    0x0C,
    0x0D,
    0x0E,
    0x0F,
    0x41,
    0x00,
    0x0F,
    0x00,
    0x00,
};
