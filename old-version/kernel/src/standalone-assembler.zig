const std = @import("std");
const Assembler = @import("assembler.zig");

var scratchpad: [4096]u8 align(16) = undefined;

pub const assembler_api = struct {
    pub const setpix = @intToPtr(fn (x: u32, y: u32, col: u32) callconv(.C) void, 0x100000);
    pub const getpix = @intToPtr(fn (x: u32, y: u32) callconv(.C) u32, 0x100004);
    pub const gettime = @intToPtr(fn () callconv(.C) u32, 0x100008);
    pub const getkey = @intToPtr(fn () callconv(.C) u32, 0x10000C);
    pub const flushpix = @intToPtr(fn () callconv(.C) void, 0x100010);
    pub const trace = @intToPtr(fn (on: u32) callconv(.C) void, 0x100014);
    pub const exit = @intToPtr(fn () callconv(.C) noreturn, 0x100016);
};

pub fn getRegisterAddress(register: u4) u32 {
    return 0x1000 + 4 * @as(u32, register);
}

pub fn main() !void {
    var contents = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, "../gasm/concept.asm", 1 << 20);

    try Assembler.assemble(std.heap.page_allocator, contents, scratchpad[0..], 0x200000);

    std.debug.print("assembled code successfully!\n", .{});

    try std.fs.cwd().writeFile("/tmp/develop.bin", scratchpad[0..]);
}
