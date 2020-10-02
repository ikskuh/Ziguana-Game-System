const Bitmap = @import("bitmap.zig").Bitmap;

pub fn BlockAllocator(comptime T: type, comptime blockCount: usize) type {
    return struct {
        const This = @This();
        const Element = T;
        const BlockCount = blockCount;

        bitmap: Bitmap(BlockCount),
        elements: [BlockCount]T,

        pub fn init() This {
            var this = This{
                .bitmap = Bitmap(BlockCount).init(.free),
                .elements = undefined,
            };
            return this;
        }

        /// free all objects
        pub fn reset(this: *This) void {
            this.bitmap = Bitmap(BlockCount).init(.free);
        }

        /// allocate single object
        pub fn alloc(this: *This) !*T {
            const idx = this.bitmap.alloc() orelse return error.OutOfMemory;
            return &this.elements[idx];
        }

        /// free previously allocated object
        pub fn free(this: *This, obj: *T) void {
            const obj_p = @ptrCast([*]T, obj);
            const root = @ptrCast([*]T, &this.elements);
            if (@ptrToInt(obj_p) < @ptrToInt(root) or @ptrToInt(obj_p) >= @ptrToInt(root + BlockCount))
                @panic("Object was not allocated with this allocator!");
            const idx = (@ptrToInt(obj_p) - @ptrToInt(root)) / @sizeOf(T);
            this.bitmap.free(idx);
        }
    };
}
