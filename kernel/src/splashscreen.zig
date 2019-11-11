const std = @import("std");
const Keyboard = @import("keyboard.zig");
const VGA = @import("vga.zig");
const Timer = @import("timer.zig");

const Point = struct {
    x: usize,
    y: usize,
    speed: usize,
};

var stars: [256]Point = undefined;

fn Bitmap2D(comptime _width: usize, comptime _height: usize) type {
    const T = struct {
        pub const stride = (width + 7) / 8;
        pub const width = _width;
        pub const height = _height;

        bits: [height * stride]u8,

        fn getPixel(this: @This(), x: usize, y: usize) u1 {
            return @truncate(u1, this.bits[stride * y + x / 8] >> @truncate(u3, x % 8));
        }
    };
    // this is currently broken
    // @compileLog(@sizeOf(T), ((_width + 7) / 8) * _height);
    // std.debug.assert(@sizeOf(T) == ((_width + 7) / 8) * _height);
    return T;
}

fn mkBitmapType(comptime bitmapData: []const u8) type {
    const W = std.mem.readIntLittle(usize, @ptrCast(*const [4]u8, &bitmapData[0]));
    const H = std.mem.readIntLittle(usize, @ptrCast(*const [4]u8, &bitmapData[4]));
    return Bitmap2D(W, H);
}

fn loadBitmap(comptime bitmapData: []const u8) mkBitmapType(bitmapData) {
    @setEvalBranchQuota(bitmapData.len);
    const T = mkBitmapType(bitmapData);
    // this is dirty, but maybe it works
    var bitmap = T{
        .bits = undefined,
    };
    std.mem.copy(u8, bitmap.bits[0..], bitmapData[8..]);
    return bitmap;
}

const logoData = loadBitmap(@embedFile("splashscreen.bin"));

const spacePressData = loadBitmap(@embedFile("splashspace.bin"));

pub extern fn run() noreturn {
    const oversampling = 4;
    var rng = std.rand.DefaultPrng.init(1);

    VGA.loadPalette([_]VGA.RGB{
        VGA.RGB.init(0x00, 0x00, 0x00), // 0
        VGA.RGB.init(0x33, 0x33, 0x33), // 1
        VGA.RGB.init(0x66, 0x66, 0x66), // 2
        VGA.RGB.init(0x99, 0x99, 0x99), // 3
        VGA.RGB.init(0xCC, 0xCC, 0xCC), // 4
        VGA.RGB.init(0xFF, 0xFF, 0xFF), // 5
        VGA.RGB.init(0xFF, 0xFF, 0xFF), // 6
    });

    for (stars) |*star| {
        star.x = rng.random.intRangeLessThan(usize, 0, oversampling * VGA.width);
        star.y = rng.random.intRangeLessThan(usize, 0, oversampling * VGA.height);
        star.speed = rng.random.intRangeAtMost(usize, 0, 3);
    }

    var floop: u8 = 0;

    while (true) {
        VGA.clear(0);

        for (stars) |*star| {
            VGA.setPixel(star.x / oversampling, star.y / oversampling, @truncate(u4, 4 - star.speed));
            star.x += oversampling * VGA.width;
            star.x -= star.speed;
            star.x %= oversampling * VGA.width;
        }

        {
            var y: usize = 0;
            while (y < @typeOf(logoData).height) : (y += 1) {
                var x: usize = 0;
                while (x < @typeOf(logoData).width) : (x += 1) {
                    var bit = logoData.getPixel(x, y);

                    if (bit == 1) {
                        const offset_x = (VGA.width - @typeOf(logoData).width) / 2;
                        const offset_y = (VGA.height - @typeOf(logoData).height) / 2;
                        VGA.setPixel(offset_x + x, offset_y + y, 6);
                        VGA.setPixel(offset_x + x + 1, offset_y + y + 1, 3);
                    }
                }
            }
        }

        if (Timer.ticks % 1500 > 750) {
            var y: usize = 0;
            while (y < @typeOf(spacePressData).height) : (y += 1) {
                var x: usize = 0;
                while (x < @typeOf(spacePressData).width) : (x += 1) {
                    var bit = spacePressData.getPixel(x, y);

                    if (bit == 1) {
                        const offset_x = (VGA.width - @typeOf(spacePressData).width) / 2;
                        const offset_y = VGA.height - 2 * @typeOf(spacePressData).height;
                        VGA.setPixel(offset_x + x, offset_y + y, 6);
                    }
                }
            }
        }

        VGA.waitForVSync();
        VGA.swapBuffers();

        Timer.wait(10);

        if (Keyboard.getKey()) |key| {
            if (key.set == .default and key.scancode == 57) {
                asm volatile ("int $0x40");
                unreachable;
            }
        }
    }
}
