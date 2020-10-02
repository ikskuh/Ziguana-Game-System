const IO = @import("io.zig");
const TextTerminal = @import("text-terminal.zig");
const std = @import("std");

// 0x00 Sekunde (BCD)
// 0x01 Alarmsekunde (BCD)
// 0x02 Minute (BCD)
// 0x03 Alarmminute (BCD)
// 0x04 Stunde (BCD)
// 0x05 Alarmstunde (BCD)
// 0x06 Wochentag (BCD)
// 0x07 Tag des Monats (BCD)
// 0x08 Monat (BCD)
// 0x09 Jahr (letzten zwei Stellen) (BCD)
// 0x0A Statusregister A
// 0x0B Statusregister B
// 0x0C Statusregister C (schreibgeschützt)
// 0x0D Statusregister D (schreibgeschützt)
// 0x0E POST-Diagnosestatusbyte
// 0x0F Shutdown-Statusbyte
// 0x10 Typ der Diskettenlaufwerke
// 0x11 reserviert
// 0x12 Typ der Festplattenlaufwerke
// 0x13 reserviert
// 0x14 Gerätebyte
// 0x15 Größe des Basisspeichers in kB (niederwertiges Byte)
// 0x16 Größe des Basisspeichers in kB (höherwertiges Byte)
// 0x17 Größe des Erweiterungsspeichers in kB (niederwertiges Byte)
// 0x18 Größe des Erweiterungsspeichers in kB (höherwertiges Byte)
// 0x19 Erweiterungsbyte 1. Festplatte
// 0x1A Erweiterungsbyte 2. Festplatte
// 0x1B - 0x2D Reserviert / vom BIOS abhängig
// 0x2E CMOS-Prüfsumme (höherwertiges Byte)
// 0x2F CMOS-Prüfsumme (niederwertiges Byte)
// 0x30 Erweiterter Speicher (niederwertiges Byte)
// 0x31 Erweiterter Speicher (höherwertiges Byte)
// 0x32 Jahrhundert (BCD)
// 0x33 - 0x3F Reserviert / vom BIOS abhängig

fn bcdDecode(val: u8) [2]u8 {
    return [2]u8{
        '0' + (val >> 4),
        '0' + (val & 0xF),
    };
}

pub fn init() void {}

pub fn printInfo() void {
    TextTerminal.println("Clock: {}:{}:{}", .{
        bcdDecode(read(0x04)),
        bcdDecode(read(0x02)),
        bcdDecode(read(0x00)),
    });

    const floppyDrives = read(0x10);

    var buf = (" " ** 64).*;

    const floppy_a_type: []const u8 = switch ((floppyDrives >> 4) & 0xF) {
        0b0000 => "none",
        0b0001 => "5 1/4 - 360 kB",
        0b0010 => "5 1/4 - 1.2 MB",
        0b0011 => "3 1/2 - 720 kB",
        0b0100 => "3 1/2 - 1.44 MB",
        else => std.fmt.bufPrint(buf[0..], "unknown ({b:0>4})", .{(floppyDrives >> 4) & 0xF}) catch unreachable,
    };

    const floppy_b_type: []const u8 = switch ((floppyDrives >> 0) & 0xF) {
        0b0000 => "none",
        0b0001 => "5 1/4 - 360 kB",
        0b0010 => "5 1/4 - 1.2 MB",
        0b0011 => "3 1/2 - 720 kB",
        0b0100 => "3 1/2 - 1.44 MB",
        else => std.fmt.bufPrint(buf[0..], "unknown ({b:0>4})", .{(floppyDrives >> 0) & 0xF}) catch unreachable,
    };

    TextTerminal.println("Floppy A: {}", .{floppy_a_type});
    TextTerminal.println("Floppy B: {}", .{floppy_b_type});
}

pub const FloppyType = enum(u4) {
    miniDD = 0b0001, // 5¼, 360 kB
    miniHD = 0b0010, // 5¼, 1200 kB
    microDD = 0b0011, // 3½, 720 kB
    microHD = 0b0100, // 3½, 1440 kB
    unknown = 0b1111,
};

pub const FloppyDrives = struct {
    A: ?FloppyType,
    B: ?FloppyType,
};

pub fn getFloppyDrives() FloppyDrives {
    const drivespec = read(0x10);

    return FloppyDrives{
        .A = switch ((drivespec >> 4) & 0xF) {
            0b0000 => null,
            0b0001 => FloppyType.miniDD,
            0b0010 => FloppyType.miniHD,
            0b0011 => FloppyType.microDD,
            0b0100 => FloppyType.microHD,
            else => FloppyType.unknown,
        },
        .B = switch ((drivespec >> 0) & 0xF) {
            0b0000 => null,
            0b0001 => FloppyType.miniDD,
            0b0010 => FloppyType.miniHD,
            0b0011 => FloppyType.microDD,
            0b0100 => FloppyType.microHD,
            else => FloppyType.unknown,
        },
    };
}

const CMOS_PORT_ADDRESS = 0x70;
const CMOS_PORT_DATA = 0x71;

fn read(offset: u7) u8 {
    const tmp = IO.in(u8, CMOS_PORT_ADDRESS);
    IO.out(u8, CMOS_PORT_ADDRESS, (tmp & 0x80) | (offset & 0x7F));
    return IO.in(u8, CMOS_PORT_DATA);
}

fn write(offset: u7, val: u8) void {
    const tmp = IO.in(u8, CMOS_PORT_ADDRESS);
    IO.out(u8, CMOS_PORT_ADDRESS, (tmp & 0x80) | (offset & 0x7F));
    IO.out(u8, CMOS_PORT_DATA, val);
}
