const std = @import("std");

pub const CHS = packed struct {
    head: u8,
    sector: u6,
    cylinder: u10,
};

pub const Partition = struct {
    const PackedData = [16]u8;

    flags: u8, // if 0x80 is set, it's bootable
    start: CHS,
    id: u8, // system id
    end: CHS,
    lba: u32,
    size: u32,

    fn unpack(data: Partition.PackedData) Partition {
        return Partition{
            .flags = data[0],
            .start = @bitCast(CHS, data[1..4].*),
            .id = data[4],
            .end = @bitCast(CHS, data[5..8].*),
            .lba = @bitCast(u32, data[8..12].*),
            .size = @bitCast(u32, data[12..16].*),
        };
    }
};

pub const BootSector = packed struct {
    bootloader: [440]u8,
    driveSignature: u32, // since win2000
    zero: u16,
    partitions: [4]Partition.PackedData,
    signature: u16 = signature,

    pub fn getPartition(self: @This(), index: u2) Partition {
        return Partition.unpack(self.partitions[index]);
    }

    pub fn isValid(hdr: BootSector) bool {
        return hdr.signature == signature;
    }
};

pub const signature = 0xAA55;

comptime {
    // @compileLog(
    //     @sizeOf(CHS),
    //     @sizeOf(Partition),
    //     @sizeOf(BootSector),
    // );
    std.debug.assert(@sizeOf(CHS) == 3);
    std.debug.assert(@sizeOf(Partition) == 16);
    std.debug.assert(@sizeOf(BootSector) == 512);
}
