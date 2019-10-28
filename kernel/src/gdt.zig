const GDT_FLAG_CODESEG = 0x0a;
const GDT_FLAG_TSS = 0x09;

const GDT_FLAG_SEGMENT = 0x10;
const GDT_FLAG_RING0 = 0x00;
const GDT_FLAG_RING3 = 0x60;
const GDT_FLAG_PRESENT = 0x80;

const GDT_FLAG_4K_GRAN = 0x800;
const GDT_FLAG_32_BIT = 0x400;

const Granularity = enum(u1) {
    byte = 0,
    page = 1,
};

const SegmentSize = enum(u1) {
    bits16 = 0,
    bits32 = 1,
};

const Descriptor = packed struct {
    pub const Access = packed struct {
        accessed: bool = false,
        writeable: bool,
        direction: bool,
        executable: bool,
        segment: bool,
        priviledge: u2,
        present: bool,
    };

    pub const Flags = packed struct {
        userbit: bool = false,
        longmode: bool,
        size: SegmentSize,
        granularity: Granularity,
    };

    limit0: u16, // 0 Limit 0-7
    // 1 Limit 8-15
    base0: u24, // 2 Base 0-7
    // 3 Base 8-15
    // 4 Base 16-23
    access: Access, // 5 Accessbyte 0-7 (vollständig)
    limit1: u4, // 6 Limit 16-19
    flags: Flags, // 6 Flags 0-3 (vollständig)
    base1: u8, // 7 Base 24-31

    pub fn init(base: u32, limit: u32, access: Access, flags: Flags) Descriptor {
        return Descriptor{
            .limit0 = @truncate(u16, limit & 0xFFFF),
            .limit1 = @truncate(u4, (limit >> 16) & 0xF),
            .base0 = @truncate(u24, base & 0xFFFFFF),
            .base1 = @truncate(u8, (base >> 24) & 0xFF),
            .access = access,
            .flags = flags,
        };
    }
};

const gdt = [_]Descriptor{
    // null descriptor
    Descriptor.init(0, 0, Descriptor.Access{
        .writeable = false,
        .direction = false,
        .executable = false,
        .segment = false,
        .priviledge = 0,
        .present = false,
    }, Descriptor.Flags{
        .granularity = .byte,
        .size = .bits16,
        .longmode = false,
    }),

    // Kernel Code Segment
    Descriptor.init(0, 0xfffff, Descriptor.Access{
        .writeable = false,
        .direction = false,
        .executable = true,
        .segment = true,
        .priviledge = 0,
        .present = true,
    }, Descriptor.Flags{
        .granularity = .page,
        .size = .bits32,
        .longmode = false,
    }),

    // Kernel Data Segment
    Descriptor.init(0, 0xfffff, Descriptor.Access{
        .writeable = true,
        .direction = false,
        .executable = false,
        .segment = true,
        .priviledge = 0,
        .present = true,
    }, Descriptor.Flags{
        .granularity = .page,
        .size = .bits32,
        .longmode = false,
    }),
};

fn load() void {
    const DescriptorTable = packed struct {
        limit: u16,
        table: [*]Descriptor,
    };

    var gdtp = DescriptorTable{
        .table = &gdt,
        .limit = @sizeOf(@typeOf(gdt)) - 1,
    };

    asm volatile ("lgdt %[gdtp]"
        :
        : [gdtp] "m" (&gdtp)
    );
}

pub fn init() void {
    load();
}
