const std = @import("std");
const PMM = @import("pmm.zig");

// WARNING: Change assembler jmp according to this!
pub const startOfUserspace = 0x40000000; // 1 GB into virtual memory
pub const sizeOfUserspace = 16 * 1024 * 1024; // 16 MB RAM
pub const endOfUserspace = startOfUserspace + sizeOfUserspace;

pub const startOfHeap = 0x80000000; // 2 GB into virtual memory
pub const sizeOfHeap = 1 * 1024 * 1024; // 1 MB
pub const endOfHeap = startOfHeap + sizeOfHeap;

pub fn getUserSpace() []u8 {
    return @intToPtr([*]u8, startOfUserspace)[0..sizeOfUserspace];
}

pub fn getHeap() []u8 {
    return @intToPtr([*]u8, startOfHeap)[0..sizeOfHeap];
}

pub fn init() !*PageDirectory {
    var directory = @intToPtr(*PageDirectory, try PMM.alloc());
    @memset(@ptrCast([*]u8, directory), 0, 4096);

    asm volatile ("mov %[ptr], %%cr3"
        :
        : [ptr] "r" (directory)
    );

    return directory;
}

pub fn createUserspace(directory: *PageDirectory) !void {
    var pointer = @as(u32, startOfUserspace);
    while (pointer < endOfUserspace) : (pointer += PMM.pageSize) {
        try directory.mapPage(pointer, try PMM.alloc(), .readWrite);
    }
}

pub fn createHeap(directory: *PageDirectory) !void {
    var pointer = @as(u32, startOfHeap);
    while (pointer < endOfHeap) : (pointer += PMM.pageSize) {
        try directory.mapPage(pointer, try PMM.alloc(), .readWrite);
    }
}

pub fn enablePaging() void {
    var cr0 = asm volatile ("mov %%cr0, %[cr]"
        : [cr] "={eax}" (-> u32)
    );
    cr0 |= (1 << 31);
    asm volatile ("mov %[cr], %%cr0"
        :
        : [cr] "{eax}" (cr0)
    );
}

pub const PageDirectory = extern struct {
    entries: [1024]Entry,

    pub fn mapPage(directory: *PageDirectory, virtualAddress: usize, physicalAddress: usize, access: WriteProtection) error{
        AlreadyMapped,
        OutOfMemory,
    }!void {
        const loc = addrToLocation(virtualAddress);

        var dirEntry = &directory.entries[loc.directoryIndex];
        if (!dirEntry.isMapped) {
            var tbl = @intToPtr(*allowzero PageTable, try PMM.alloc());
            @memset(@ptrCast([*]u8, tbl), 0, 4096);

            dirEntry.* = Entry{
                .isMapped = true,
                .writeProtection = .readWrite,
                .access = .ring0,
                .enableWriteThroughCaching = false,
                .disableCaching = false,
                .wasAccessed = false,
                .wasWritten = false,
                .size = .fourKilo,
                .dontRefreshTLB = false,
                .userBits = 0,
                // Hack to workaround #2627
                .pointer0 = @truncate(u4, (@ptrToInt(tbl) >> 12)),
                .pointer1 = @intCast(u16, (@ptrToInt(tbl) >> 16)),
            };

            std.debug.assert(@ptrToInt(tbl) == (@bitCast(usize, dirEntry.*) & 0xFFFFF000));
        }

        var table = @intToPtr(*allowzero PageTable, ((@as(usize, dirEntry.pointer1) << 4) | @as(usize, dirEntry.pointer0)) << 12);

        var tblEntry = &table.entries[loc.tableIndex];

        if (tblEntry.isMapped) {
            // Terminal.println("Mapping is at {} is {X}: {}", loc, @bitCast(u32, tblEntry.*), tblEntry);
            return error.AlreadyMapped;
        }

        tblEntry.* = Entry{
            .isMapped = true,
            .writeProtection = access,
            .access = .ring0,
            .enableWriteThroughCaching = false,
            .disableCaching = false,
            .wasAccessed = false,
            .wasWritten = false,
            .size = .fourKilo,
            .dontRefreshTLB = false,
            .userBits = 0,
            // Hack to workaround #2627
            .pointer0 = @truncate(u4, (physicalAddress >> 12)),
            .pointer1 = @intCast(u16, (physicalAddress >> 16)),
        };

        std.debug.assert(physicalAddress == (@bitCast(usize, tblEntry.*) & 0xFFFFF000));

        asm volatile ("invlpg %[ptr]"
            :
            : [ptr] "m" (virtualAddress)
        );
    }
};

const PageTable = extern struct {
    entries: [1024]Entry,
};

const PageLocation = struct {
    directoryIndex: u10,
    tableIndex: u10,
};

fn addrToLocation(addr: usize) PageLocation {
    const idx = addr / 4096;
    return PageLocation{
        .directoryIndex = @truncate(u10, idx / 1024),
        .tableIndex = @truncate(u10, idx & 0x3FF),
    };
}

const WriteProtection = enum(u1) {
    readOnly = 0,
    readWrite = 1,
};

const PageAccess = enum(u1) {
    ring0 = 0,
    all = 1,
};

const PageSize = enum(u1) {
    fourKilo = 0,
    fourMegas = 1,
};

const Entry = packed struct {
    isMapped: bool,
    writeProtection: WriteProtection,
    access: PageAccess,
    enableWriteThroughCaching: bool,
    disableCaching: bool,
    wasAccessed: bool,
    wasWritten: bool,
    size: PageSize,
    dontRefreshTLB: bool,
    userBits: u3 = 0,

    // magic bug fix for #2627
    pointer0: u4,
    pointer1: u16,
};

comptime {
    std.debug.assert(@sizeOf(Entry) == 4);
    std.debug.assert(@sizeOf(PageDirectory) == 4096);
    std.debug.assert(@sizeOf(PageTable) == 4096);
}
