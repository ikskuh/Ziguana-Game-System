const std = @import("std");

pub const IteratorKind = enum {
    mutable,
    constant,
};

pub fn BlockIterator(kind: IteratorKind) type {
    return struct {
        const This = @This();
        const Slice = switch (kind) {
            .mutable => []u8,
            .constant => []const u8,
        };

        slice: Slice,
        offset: usize,
        blockSize: usize,
        block: usize,

        pub fn init(block: usize, buffer: Slice, blockSize: usize) !This {
            if (!std.math.isPowerOfTwo(blockSize))
                return error.BlockSizeMustBePowerOfTwo;
            if (!std.mem.isAligned(buffer.len, blockSize))
                return error.BufferLengthMustBeMultipleOfBlockSize;
            return This{
                .slice = buffer,
                .offset = 0,
                .blockSize = blockSize,
                .block = block,
            };
        }

        pub fn next(this: *This) ?Block {
            if (this.offset >= this.slice.len)
                return null;
            var block = Block{
                .block = this.block,
                .slice = this.slice[this.offset .. this.offset + this.blockSize],
            };
            this.offset += this.blockSize;
            this.block += 1;
            return block;
        }

        pub const Block = struct {
            slice: Slice,
            block: usize,
        };
    };
}
