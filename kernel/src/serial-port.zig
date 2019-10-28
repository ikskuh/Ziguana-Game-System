const io = @import("io.zig");

pub const IER = 1;
pub const IIR = 2;
pub const FCR = 2;
pub const LCR = 3;
pub const MCR = 4;
pub const LSR = 5;
pub const MSR = 6;

// Prüft, ob man bereits schreiben kann
pub fn is_transmit_empty(base: u16) bool {
    return (io.inb(base + LSR) & 0x20) != 0;
}

// Byte senden
fn write_com(base: u16, chr: u8) void {
    while (!is_transmit_empty(base)) {}
    io.outb(base, chr);
}

pub fn put(c: u8) void {
    write_com(0x3F8, c);
}

pub fn write(message: []u8) void {
    for (message) |c| {
        put(c);
    }
}
