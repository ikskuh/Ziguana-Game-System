const std = @import("std");

pub fn BitmapAllocator(comptime BitCount: comptime_int) type {
    std.debug.assert((BitCount & 0x1F) == 0);
    return struct {
        const This = @This();
        const WordCount = BitCount / 32;

        pub const Marker = enum {
            free,
            allocated,
        };

        /// one bit for each page in RAM.
        /// If the bit is set, the corresponding page is free.
        bitmap: [WordCount]u32,

        pub fn init() This {
            return This{
                // everything is allocated
                .bitmap = [_]u32{0} ** WordCount,
            };
        }

        pub fn allocPage(this: *This) ?usize {
            for (this.bitmap) |*bits, i| {
                if (bits.* == 0)
                    continue;
                comptime var b = 0;
                inline while (b < 32) : (b += 1) {
                    const bitmask = (1 << b);
                    if ((bits.* & bitmask) != 0) {
                        bits.* &= ~u32(bitmask);
                        return 4096 * (32 * i + b);
                    }
                }
                unreachable;
            }
            return null;
        }

        pub fn markPage(this: *This, ptr: usize, marker: Marker) void {
            std.debug.assert(std.mem.isAligned(ptr, 4096));
            const page = ptr / 4096;
            const i = page / 32;
            const b = @truncate(u5, page % 32);
            switch (marker) {
                .allocated => this.bitmap[i] &= ~(u32(1) << b),
                .free => this.bitmap[i] |= (u32(1) << b),
            }
        }

        pub fn freePage(this: *This, ptr: usize) void {
            this.markPage(ptr, .free);
        }

        pub fn getFreePageCount(this: This) usize {
            var count: usize = 0;
            for (this.bitmap) |bits, i| {
                count += @popCount(u32, bits);
            }
            return count;
        }
    };
}

test "BitmapAllocator" {
    // fails horribly with 63. compiler bug!
    var allocator = BitmapAllocator(64).init();
    std.debug.assert(allocator.bitmap.len == 2);

    std.debug.assert(allocator.allocPage() == null);
    std.debug.assert(allocator.allocPage() == null);
    std.debug.assert(allocator.allocPage() == null);
}

test "BitmapAllocator.tight" {
    var allocator = BitmapAllocator(64).init();

    allocator.markPage(0x0000, .free);
    allocator.markPage(0x1000, .free);

    std.debug.assert(allocator.getFreePageCount() == 2);

    std.debug.assert(allocator.allocPage().? == 0x0000);

    std.debug.assert(allocator.getFreePageCount() == 1);

    std.debug.assert(allocator.allocPage().? == 0x1000);

    std.debug.assert(allocator.getFreePageCount() == 0);

    allocator.freePage(0x1000);

    std.debug.assert(allocator.getFreePageCount() == 1);

    std.debug.assert(allocator.allocPage().? == 0x1000);

    std.debug.assert(allocator.getFreePageCount() == 0);

    std.debug.assert(allocator.allocPage() == null);

    std.debug.assert(allocator.getFreePageCount() == 0);
}

test "BitmapAllocator.sparse" {
    var allocator = BitmapAllocator(64).init();

    allocator.markPage(0x04000, .free);
    allocator.markPage(0x24000, .free);

    std.debug.assert(allocator.allocPage().? == 0x04000);
    std.debug.assert(allocator.allocPage().? == 0x24000);
    std.debug.assert(allocator.allocPage() == null);
}

test "BitmapAllocator.heavy" {
    var allocator = BitmapAllocator(64).init();

    comptime var i = 0;
    inline while (i < 64) : (i += 1) {
        allocator.markPage(0x1000 * i, .free);
    }
    std.debug.assert(allocator.getFreePageCount() == 64);

    comptime i = 0;
    inline while (i < 64) : (i += 1) {
        std.debug.assert(allocator.allocPage().? == 0x1000 * i);
    }

    std.debug.assert(allocator.allocPage() == null);
}
