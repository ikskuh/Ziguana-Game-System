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
    .reallocFn = realloc,
    .shrinkFn = shrink,
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

fn realloc(
    self: *std.mem.Allocator,
    /// Guaranteed to be the same as what was returned from most recent call to
    /// `reallocFn` or `shrinkFn`.
    /// If `old_mem.len == 0` then this is a new allocation and `new_byte_count`
    /// is guaranteed to be >= 1.
    old_mem: []u8,
    /// If `old_mem.len == 0` then this is `undefined`, otherwise:
    /// Guaranteed to be the same as what was returned from most recent call to
    /// `reallocFn` or `shrinkFn`.
    /// Guaranteed to be >= 1.
    /// Guaranteed to be a power of 2.
    old_alignment: u29,
    /// If `new_byte_count` is 0 then this is a free and it is guaranteed that
    /// `old_mem.len != 0`.
    new_byte_count: usize,
    /// Guaranteed to be >= 1.
    /// Guaranteed to be a power of 2.
    /// Returned slice's pointer must have this alignment.
    new_alignment: u29,
) std.mem.Allocator.Error![]u8 {
    if (old_mem.len == 0) {
        // Terminal.println("malloc({})", new_byte_count);
        if (new_alignment > granularity)
            @panic("invalid alignment!");
        var mem = malloc(new_byte_count);
        printAllocationList();
        return mem;
    } else if (new_byte_count == 0) {
        // Terminal.println("free({}", old_mem.ptr);
        free(old_mem);
        printAllocationList();
        return &[0]u8{};
    } else {
        // Terminal.println("realloc({}, {})", old_mem.ptr, new_byte_count);
        std.debug.assert(old_mem.len <= new_byte_count);
        var new = try malloc(new_byte_count);
        std.mem.copy(u8, new, old_mem);
        free(old_mem);
        printAllocationList();
        return new;
    }
}

fn shrink(
    self: *std.mem.Allocator,
    /// Guaranteed to be the same as what was returned from most recent call to
    /// `reallocFn` or `shrinkFn`.
    old_mem: []u8,
    /// Guaranteed to be the same as what was returned from most recent call to
    /// `reallocFn` or `shrinkFn`.
    old_alignment: u29,
    /// Guaranteed to be less than or equal to `old_mem.len`.
    new_byte_count: usize,
    /// If `new_byte_count == 0` then this is `undefined`, otherwise:
    /// Guaranteed to be less than or equal to `old_alignment`.
    new_alignment: u29,
) []u8 {
    if (new_byte_count == 0) {
        // Terminal.println("free'({}", old_mem.ptr);
        free(old_mem);
        printAllocationList();
        return &[0]u8{};
    } else {
        printAllocationList();
        // Terminal.println("shrink(old_mem={}, old_alignment={}, new_byte_count={}, new_alignment={})\n", old_mem.len, old_alignment, new_byte_count, new_alignment);
        @panic("not implemented yet");
    }
}
