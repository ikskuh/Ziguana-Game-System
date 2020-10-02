const std = @import("std");
const VMM = @import("vmm.zig");

/// defines the minimum size of an allocation
const granularity = 16;

const HeapSegment = struct {
    const This = @This();

    next: ?*This,
    size: usize,
    isFree: bool,
};

comptime {
    std.debug.assert(@alignOf(HeapSegment) <= granularity);
    std.debug.assert(@sizeOf(HeapSegment) <= granularity);
    std.debug.assert(std.mem.isAligned(VMM.startOfHeap, granularity));
    std.debug.assert(std.mem.isAligned(VMM.endOfHeap, granularity));
}

var allocatorObject = std.mem.Allocator{
    .allocFn = heapAlloc,
    .resizeFn = heapResize,
};

pub const allocator = &allocatorObject;

var firstNode: ?*HeapSegment = null;

pub fn init() void {
    firstNode = @intToPtr(*HeapSegment, VMM.startOfHeap);
    firstNode.?.* = HeapSegment{
        .next = null,
        .size = VMM.sizeOfHeap,
        .isFree = true,
    };
}

fn malloc(len: usize) std.mem.Allocator.Error![]u8 {
    var node = firstNode;
    while (node) |it| : (node = it.next) {
        if (!it.isFree)
            continue;
        if (it.size - granularity < len)
            continue;

        const address_of_node = @ptrToInt(it);
        std.debug.assert(std.mem.isAligned(address_of_node, granularity)); // security check here

        const address_of_data = address_of_node + granularity;

        const new_size_of_node = std.mem.alignForward(len, granularity) + granularity;

        // if we haven't allocated *all* memory in this node
        if (it.size > new_size_of_node) {
            const remaining_size = it.size - new_size_of_node;
            it.size = new_size_of_node;

            const address_of_next = address_of_node + new_size_of_node;
            std.debug.assert(std.mem.isAligned(address_of_next, granularity)); // security check here

            const next = @intToPtr(*HeapSegment, address_of_next);
            next.* = HeapSegment{
                .size = remaining_size,
                .isFree = true,
                .next = it.next,
            };
            it.next = next;
        }

        it.isFree = false;
        return @intToPtr([*]u8, address_of_data)[0..len];
    }
    return error.OutOfMemory;
}

fn free(memory: []u8) void {
    const address_of_data = @ptrToInt(memory.ptr);
    std.debug.assert(std.mem.isAligned(address_of_data, granularity)); // security check here
    const address_of_node = address_of_data - granularity;

    const node = @intToPtr(*HeapSegment, address_of_node);
    node.isFree = true;

    if (node.next) |next| {
        // sad, we cannot merge :(
        if (!next.isFree)
            return;

        node.size += next.size;

        // make sure this is the last access to "next",
        // because: zig bug!
        node.next = next.next;
    }
}

fn printAllocationList() void {
    // var node = firstNode;
    // while (node) |it| : (node = it.next) {
    //     Terminal.println("{*} = {{ .size = {}, .isFree = {}, .next = {*} }}", it, it.size, it.isFree, it.next);
    // }
}

fn heapAlloc(self: *std.mem.Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) std.mem.Allocator.Error![]u8 {
    std.debug.assert(ptr_align <= @alignOf(c_longdouble));
    return try malloc(len);
}

fn heapResize(
    self: *std.mem.Allocator,
    buf: []u8,
    old_align: u29,
    new_len: usize,
    len_align: u29,
    ret_addr: usize,
) std.mem.Allocator.Error!usize {
    if (new_len == 0) {
        free(buf);
        return 0;
    }
    if (new_len <= buf.len) {
        return std.mem.alignAllocLen(buf.len, new_len, len_align);
    }
    return error.OutOfMemory;
}
