const Bitmap = @import("bitmap.zig").Bitmap;

pub const pageSize = 0x1000;
pub const totalPageCount = (1 << 32) / pageSize;

// 1 MBit for 4 GB @ 4096 pages
var pmm_bitmap = Bitmap(totalPageCount).init(.allocated);

pub fn alloc() !usize {
    return pageSize * (pmm_bitmap.alloc() orelse return error.OutOfMemory);
}

pub fn free(ptr: usize) void {
    pmm_bitmap.free(ptr / pageSize);
}

pub const Marker = @import("bitmap.zig").Marker;

pub fn mark(ptr: usize, marker: Marker) void {
    pmm_bitmap.mark(ptr / pageSize, marker);
}

pub fn getFreePageCount() usize {
    return pmm_bitmap.getFreeCount();
}

pub fn getFreeMemory() usize {
    return pageSize * pmm_bitmap.getFreeCount();
}
