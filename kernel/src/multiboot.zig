const std = @import("std");

pub const Header = packed struct {
    magic: u32 = 0x1badb002,
    flags: Flags = 0,
    checksum: u32 = 0,

    header_addr: u32 = 0,
    load_addr: u32 = 0,
    load_end_addr: u32 = 0,
    bss_end_addr: u32 = 0,
    entry_addr: u32 = 0,

    mode_type: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    depth: u32 = 0,

    const Flags = packed struct {
        aligned: bool,
        provideMmap: bool,
        provideVideoMode: bool,
        _0: u12 = 0,
        overrideLoadAddress: bool,
        _1: u16 = 0,
    };

    comptime {
        std.debug.assert(@sizeOf(Flags) == 4);
    }

    pub fn init() Header {
        var header = Header{
            .flags = Flags{
                .aligned = true,
                .provideMmap = true,
                .provideVideoMode = false,
                .overrideLoadAddress = false,
            },
        };
        header.checksum = calcChecksum(&header);

        // // Validate header checksum
        // var cs: u32 = 0;
        // inline for (@typeInfo(@This()).Struct.fields) |fld| {
        //     _ = @addWithOverflow(u32, cs, @bitCast(u32, @field(header, fld.name)), &cs);
        // }
        // std.debug.assert(cs == 0);

        return header;
    }

    fn calcChecksum(header: *Header) u32 {
        var cs: u32 = 0;

        // inline for (@typeInfo(@This()).Struct.fields) |fld| {
        //     if (!std.mem.eql(u8, fld.name, "checksum")) {
        //         _ = @subWithOverflow(u32, cs, @bitCast(u32, @field(header, fld.name)), &cs);
        //     }
        // }
        _ = @subWithOverflow(u32, cs, @bitCast(u32, header.flags), &cs);
        _ = @subWithOverflow(u32, cs, @bitCast(u32, header.magic), &cs);

        return cs;
    }
};

pub const Structure = packed struct {
    flags: u32,

    mem: Memory,

    boot_device: u32,
    cmdline: [*]u8,
    mods: Modules,
    syms: [4]u32,
    mmap: MemoryMap,
    drives: Drives,
    config_table: u32,
    boot_loader_name: [*]u8,
    apm_table: u32,
    vbe: VesaBiosExtensions,
    framebuffer: Framebuffer,

    pub const Flags = packed struct {
        mem: bool,
        boot_device: bool,
        cmdline: bool,
        mods: bool,
        syms: bool,
        syms2: bool,
        mmap: bool,
        drives: bool,
        config_table: bool,
        boot_loader_name: bool,
        apm_table: bool,
        vbe: bool,
        framebuffer: bool,

        // WORKAROUND: This is a compiler bug, see
        // https://github.com/ziglang/zig/issues/2627
        _0: u3,
        _1: u16,
    };

    pub const Modules = extern struct {
        mods_count: u32,
        mods_addr: u32,
    };

    pub const Memory = extern struct {
        lower: u32,
        upper: u32,
    };

    pub const MemoryMap = extern struct {
        mmap_length: u32,
        mmap_addr: u32,

        const Type = enum(u32) {
            available = 1,
            reserved = 2,
            acpi = 3,
            reservedForHibernation = 4,
            defectiveRAM = 5,
        };

        const Entry = packed struct {
            size: u32,
            baseAddress: u64,
            length: u64,
            type: Type,
        };

        const Iterator = struct {
            end_pos: u32,
            current_pos: u32,

            pub fn next(this: *Iterator) ?*const Entry {
                // official multiboot documentation is bad here :(
                // this is the right way to iterate over the multiboot structure
                if (this.current_pos >= this.end_pos) {
                    return null;
                } else {
                    var current = @intToPtr(*const Entry, this.current_pos);
                    this.current_pos += (current.size + 0x04);
                    return current;
                }
            }
        };

        fn iterator(this: MemoryMap) Iterator {
            return Iterator{
                .end_pos = this.mmap_addr + this.mmap_length,
                .current_pos = this.mmap_addr,
            };
        }
    };

    pub const Drives = extern struct {
        drives_length: u32,
        drives_addr: u32,
    };

    pub const VesaBiosExtensions = extern struct {
        control_info: u32,
        mode_info: u32,
        mode: u16,
        interface_seg: u16,
        interface_off: u16,
        interface_len: u16,
    };

    pub const Framebuffer = extern struct {
        addr_low: u32,
        addr_high: u32,
        pitch: u32,
        width: u32,
        height: u32,
        bpp: u8,
        type: u8,
        color_info: [5]u8,
    };

    comptime {
        std.debug.assert(std.meta.fieldInfo(@This(), "mem").offset.? == 4);
        std.debug.assert(std.meta.fieldInfo(@This(), "vbe").offset.? == 72);
        std.debug.assert(std.meta.fieldInfo(@This(), "framebuffer").offset.? == 88);
    }
};
