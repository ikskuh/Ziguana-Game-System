const std = @import("std");
const Assembler = @import("assembler.zig");

var scratchpad: [4096]u8 align(16) = undefined;

pub fn main() !void {
    var contents = try std.io.readFileAlloc(std.heap.direct_allocator, "../gasm/concept.asm");

    try Assembler.assemble(std.heap.direct_allocator, contents, scratchpad[0..]);

    std.debug.warn("assembled code successfully!\n");
}
