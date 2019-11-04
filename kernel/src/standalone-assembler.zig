const std = @import("std");
const Assembler = @import("assembler.zig");

var scratchpad: [4096]u8 align(16) = undefined;

pub const assembler_api = struct {
    pub const setpix = @intToPtr(extern fn (x: u32, y: u32, col: u32) void, 0x100000);
    pub const getpix = @intToPtr(extern fn (x: u32, y: u32) u32, 0x100004);
    pub const gettime = @intToPtr(extern fn () u32, 0x100008);
    pub const getkey = @intToPtr(extern fn () u32, 0x10000C);
};

pub fn main() !void {
    var contents = try std.io.readFileAlloc(std.heap.direct_allocator, "../gasm/develop.asm");

    try Assembler.assemble(std.heap.direct_allocator, contents, scratchpad[0..], 0x200000);

    std.debug.warn("assembled code successfully!\n");

    try std.io.writeFile("/tmp/develop.gasm", scratchpad[0..]);
}
