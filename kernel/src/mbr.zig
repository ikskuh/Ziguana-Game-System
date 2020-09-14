const std = @import("std");

pub const CHS = packed struct {
    head: u8,
    sector: u6,
    cylinder: u10,
};

pub const Partition = packed struct {
    flags: u8,
    start: CHS,
    id: u8,
    end: CHS,
    lba: u32,
    size: u32,
};

pub const BootSector = packed struct {
    bootloader: [440]u8,
    driveSignature: u32, // since win2000
    zero: u16,
    partitions: [4]Partition,
    signature: u16 = signature,

    pub fn isValid(hdr: BootSector) bool {
        return hdr.signature == signature;
    }
};

pub const signature = 0xAA55;

comptime {
    std.debug.assert(@sizeOf(CHS) == 3);
    std.debug.assert(@sizeOf(Partition) == 16);
    std.debug.assert(@sizeOf(BootSector) == 512);
}
