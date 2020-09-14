const std = @import("std");

pub const FSHeader = packed struct {
    magic: u32 = 0x56ac65d5, // 0x56ac65d5
    version: u32 = 1,
    name: [32]u8, // zero-terminated or full
    saveGameSize: u32,

    pub fn isValid(hdr: FSHeader) bool {
        return (hdr.magic == 0x56AC65D5) and (hdr.version == 1);
    }

    pub fn getName(hdr: FSHeader) []const u8 {
        return hdr.name[0 .. std.mem.indexOf(u8, hdr.name, "\x00") orelse hdr.name.len];
    }

    pub fn supportsSaveGames(hdr: FSHeader) bool {
      return hdr.saveGameSize != 0;
    }
};

comptime {
    std.debug.assert(@sizeOf(FSHeader) <= 512);
}
