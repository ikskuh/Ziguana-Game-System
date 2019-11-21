const io = @import("io.zig");

pub const IER = 1;
pub const IIR = 2;
pub const FCR = 2;
pub const LCR = 3;
pub const MCR = 4;
pub const LSR = 5;
pub const MSR = 6;

pub const COM1 = 0x3F8;
pub const COM2 = 0x2F8;
pub const COM3 = 0x3E8;
pub const COM4 = 0x2E8;

// Prüft, ob man bereits schreiben kann
pub fn is_transmit_empty(base: u16) bool {
    return (io.in(u8, base + LSR) & 0x20) != 0;
}

// Byte senden
fn write_com(base: u16, chr: u8) void {
    while (!is_transmit_empty(base)) {}
    io.out(u8, base, chr);
}

pub fn put(c: u8) void {
    write_com(COM1, c);
}

pub fn write(message: []u8) void {
    for (message) |c| {
        put(c);
    }
}

pub const Parity = enum(u3) {
    none = 0,
    odd = 0b100,
    even = 0b110,
    mark = 0b101,
    zero = 0b111,
};

pub const BitCount = enum(u4) {
    five = 5,
    six = 6,
    seven = 7,
    eight = 8,
};

// Funktion zum initialisieren eines COM-Ports
pub fn init(base: u16, baud: usize, parity: Parity, bits: BitCount) void {
    // Teiler berechnen
    const baudSplits = @bitCast([2]u8, @intCast(u16, 115200 / baud));

    // Interrupt ausschalten
    io.out(u8, base + IER, 0x00);

    // DLAB-Bit setzen
    io.out(u8, base + LCR, 0x80);

    // Teiler (low) setzen
    io.out(u8, base + 0, baudSplits[0]);

    // Teiler (high) setzen
    io.out(u8, base + 1, baudSplits[1]);

    // Anzahl Bits, Parität, usw setzen (DLAB zurücksetzen)
    io.out(u8, base + LCR, ((@enumToInt(parity) & 0x7) << 3) | ((@enumToInt(bits) - 5) & 0x3));

    // Initialisierung abschließen
    io.out(u8, base + FCR, 0xC7);
    io.out(u8, base + MCR, 0x0B);
}
