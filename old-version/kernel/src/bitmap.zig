const std = @import("std");

pub const Marker = enum {
    free,
    allocated,
};

pub fn Bitmap(comptime BitCount: comptime_int) type {
    return struct {
        const This = @This();
        const BitPerWord = @typeInfo(usize).Int.bits;
        const WordCount = (BitCount + BitPerWord - 1) / BitPerWord;

        /// one bit for each page in RAM.
        /// If the bit is set, the corresponding page is free.
        bitmap: [WordCount]usize,

        pub fn init(marker: Marker) This {
            return This{
                // everything is allocated
                .bitmap = switch (marker) {
                    .free => [_]usize{std.math.maxInt(usize)} ** WordCount,
                    .allocated => [_]usize{0} ** WordCount,
                },
            };
        }

        pub fn alloc(this: *This) ?usize {
            for (this.bitmap) |*bits, i| {
                if (bits.* == 0)
                    continue;
                comptime var b = 0;
                inline while (b < BitPerWord) : (b += 1) {
                    const bitmask = (1 << b);
                    if ((bits.* & bitmask) != 0) {
                        bits.* &= ~@as(usize, bitmask);
                        return (BitPerWord * i + b);
                    }
                }
                unreachable;
            }
            return null;
        }

        pub fn mark(this: *This, bit: usize, marker: Marker) void {
            const i = bit / BitPerWord;
            const b = @truncate(u5, bit % BitPerWord);
            switch (marker) {
                .allocated => this.bitmap[i] &= ~(@as(usize, 1) << b),
                .free => this.bitmap[i] |= (@as(usize, 1) << b),
            }
        }

        pub fn free(this: *This, bit: usize) void {
            this.mark(bit, .free);
        }

        pub fn getFreeCount(this: This) usize {
            var count: usize = 0;
            for (this.bitmap) |bits, i| {
                count += @popCount(usize, bits);
            }
            return count;
        }
    };
}

test "Bitmap" {
    // fails horribly with 63. compiler bug!
    var allocator = Bitmap(64).init();
    std.debug.assert(allocator.bitmap.len == 2);

    std.debug.assert(allocator.alloc() == null);
    std.debug.assert(allocator.alloc() == null);
    std.debug.assert(allocator.alloc() == null);
}

test "Bitmap.tight" {
    var allocator = Bitmap(64).init();

    allocator.mark(0, .free);
    allocator.mark(1, .free);

    std.debug.assert(allocator.getFreeCount() == 2);

    std.debug.assert(allocator.alloc().? == 0);

    std.debug.assert(allocator.getFreeCount() == 1);

    std.debug.assert(allocator.alloc().? == 1);

    std.debug.assert(allocator.getFreeCount() == 0);

    allocator.free(1);

    std.debug.assert(allocator.getFreeCount() == 1);

    std.debug.assert(allocator.alloc().? == 1);

    std.debug.assert(allocator.getFreeCount() == 0);

    std.debug.assert(allocator.alloc() == null);

    std.debug.assert(allocator.getFreeCount() == 0);
}

test "Bitmap.sparse" {
    var allocator = Bitmap(64).init();

    allocator.mark(0x04, .free);
    allocator.mark(0x24, .free);

    std.debug.assert(allocator.alloc().? == 0x04);
    std.debug.assert(allocator.alloc().? == 0x24);
    std.debug.assert(allocator.alloc() == null);
}

test "Bitmap.heavy" {
    var allocator = Bitmap(64).init();

    comptime var i = 0;
    inline while (i < 64) : (i += 1) {
        allocator.mark(i, .free);
    }
    std.debug.assert(allocator.getFreeCount() == 64);

    comptime i = 0;
    inline while (i < 64) : (i += 1) {
        std.debug.assert(allocator.alloc().? == i);
    }

    std.debug.assert(allocator.alloc() == null);
}
