const Error = error{AddressNotOnDevice};

pub const DriveLayout = struct {
    headCount: usize,
    cylinderCount: usize,
    sectorCount: usize,
};

pub const CHS = struct {
    cylinder: usize, // starts at 0
    head: usize, // starts at 0
    sector: usize, // starts at 1
};

pub fn lba2chs(layout: DriveLayout, lba: usize) Error!CHS {
    if (lba >= layout.headCount * layout.cylinderCount * layout.sectorCount)
        return error.AddressNotOnDevice;
    return CHS{
        .cylinder = lba / (layout.headCount * layout.sectorCount),
        .head = ((lba % (layout.headCount * layout.sectorCount)) / layout.sectorCount),
        .sector = ((lba % (layout.headCount * layout.sectorCount)) % layout.sectorCount + 1),
    };
}

pub fn chs2lba(layout: DriveLayout, chs: CHS) Error!usize {
    if (chs.sector < 1 or chs.sector > layout.sectorCount)
        return error.AddressNotOnDevice;
    if (chs.head >= layout.headCount)
        return error.AddressNotOnDevice;
    if (chs.cylinder >= layout.cylinderCount)
        return error.AddressNotOnDevice;
    return layout.sectorCount * layout.headCount * chs.cylinder + layout.sectorCount * chs.head + chs.sector - 1;
}

const std = @import("std");

test "lba2chs" {
    const layout = DriveLayout{
        .headCount = 2,
        .cylinderCount = 3,
        .sectorCount = 5,
    };

    std.debug.assert(std.meta.eql(try lba2chs(layout, 0), CHS{ .cylinder = 0, .head = 0, .sector = 1 }));
    std.debug.assert(std.meta.eql(try lba2chs(layout, 4), CHS{ .cylinder = 0, .head = 0, .sector = 5 }));
    std.debug.assert(std.meta.eql(try lba2chs(layout, 5), CHS{ .cylinder = 0, .head = 1, .sector = 1 }));
    std.debug.assert(std.meta.eql(try lba2chs(layout, 10), CHS{ .cylinder = 1, .head = 0, .sector = 1 }));

    std.debug.assert(std.meta.eql(try lba2chs(layout, 3), CHS{ .cylinder = 0, .head = 0, .sector = 4 }));
    std.debug.assert(std.meta.eql(try lba2chs(layout, 7), CHS{ .cylinder = 0, .head = 1, .sector = 3 }));
    std.debug.assert(std.meta.eql(try lba2chs(layout, 19), CHS{ .cylinder = 1, .head = 1, .sector = 5 }));
}

test "chs2lba" {
    const layout = DriveLayout{
        .headCount = 2,
        .cylinderCount = 3,
        .sectorCount = 5,
    };

    std.debug.assert((try chs2lba(layout, CHS{ .cylinder = 0, .head = 0, .sector = 5 })) == 4);
    std.debug.assert((try chs2lba(layout, CHS{ .cylinder = 0, .head = 1, .sector = 1 })) == 5);
    std.debug.assert((try chs2lba(layout, CHS{ .cylinder = 1, .head = 0, .sector = 1 })) == 10);

    std.debug.assert((try chs2lba(layout, CHS{ .cylinder = 0, .head = 0, .sector = 4 })) == 3);
    std.debug.assert((try chs2lba(layout, CHS{ .cylinder = 0, .head = 1, .sector = 3 })) == 7);
    std.debug.assert((try chs2lba(layout, CHS{ .cylinder = 1, .head = 1, .sector = 5 })) == 19);
}
